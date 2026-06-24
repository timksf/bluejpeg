import os
import struct
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.handle import Force, Release
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, with_timeout
from PIL import Image


UART_BIT_CYCLES = int(os.environ.get("UART_BIT_CYCLES", "4"))
UART_IDLE_TIMEOUT_BITS = int(os.environ.get("TOP_UART_IDLE_TIMEOUT_BITS", "64"))

ROUTE_CTRL = ord("C")
ROUTE_DATA = ord("D")
UART_AXI_READ = 0x00
UART_AXI_WRITE = 0x01
UART_AXI_STATUS_OK = 0x00

CTRL_ADDR = 0x04
STS_ADDR = 0x08
IMSZ_ADDR = 0x0C
SUBS_ADDR = 0x10
CGEN_ADDR = 0x14
STS_RDY_BIT = 0
STS_CGB_BIT = 1
CGEN_TRIGGER = 0x80000000


def load_bmp_array(path: Path) -> np.ndarray:
    image = Image.open(path).convert("RGB")
    return np.asarray(image, dtype=np.uint8)


def rgb_to_ycbcr(red: int, green: int, blue: int):
    y = 0.299 * red + 0.587 * green + 0.114 * blue
    cb = -0.168736 * red - 0.331264 * green + 0.5 * blue + 128.0
    cr = 0.5 * red - 0.418688 * green - 0.081312 * blue + 128.0

    def clamp(channel: float) -> int:
        return int(max(0.0, min(255.0, channel)))

    return clamp(y), clamp(cb), clamp(cr)


def pack_ycbcr_pixels(rgb_array: np.ndarray):
    payload = bytearray()
    flat_pixels = rgb_array.reshape(-1, 3)
    for red, green, blue in flat_pixels:
        y, cb, cr = rgb_to_ycbcr(red, green, blue)
        payload.extend((cr, cb, y))
    return bytes(payload)


def parse_jpeg_dimensions(payload: bytes):
    if len(payload) < 4 or payload[:2] != b"\xff\xd8":
        raise AssertionError("JPEG output is missing the SOI marker")
    if payload[-2:] != b"\xff\xd9":
        raise AssertionError("JPEG output is missing the EOI marker")

    sof_markers = {
        0xC0,
        0xC1,
        0xC2,
        0xC3,
        0xC5,
        0xC6,
        0xC7,
        0xC9,
        0xCA,
        0xCB,
        0xCD,
        0xCE,
        0xCF,
    }

    index = 2
    while index < len(payload):
        if payload[index] != 0xFF:
            index += 1
            continue

        while index < len(payload) and payload[index] == 0xFF:
            index += 1
        if index >= len(payload):
            break

        marker = payload[index]
        index += 1

        if marker == 0xD9:
            break
        if marker == 0xD8 or marker == 0x01 or 0xD0 <= marker <= 0xD7:
            continue

        if index + 2 > len(payload):
            break

        segment_length = struct.unpack_from(">H", payload, index)[0]
        if segment_length < 2 or index + segment_length > len(payload):
            raise AssertionError("JPEG output contains an invalid segment length")

        if marker in sof_markers:
            height = struct.unpack_from(">H", payload, index + 3)[0]
            width = struct.unpack_from(">H", payload, index + 5)[0]
            return width, height

        index += segment_length

    raise AssertionError("JPEG output is missing a start-of-frame marker")


def signal_is_high(signal) -> bool:
    value = signal.value
    if not value.is_resolvable:
        return False
    return bool(int(value))


def led_bit_is_high(dut, bit_index: int) -> bool:
    value = dut.led.value
    if not value.is_resolvable:
        return False
    return bool(int(value) & (1 << bit_index))


async def wait_for_high(signal, clock, max_cycles: int, name: str):
    for _ in range(max_cycles):
        if signal_is_high(signal):
            return
        await RisingEdge(clock)
    raise TimeoutError(f"Timed out waiting for {name}")


async def wait_for_led_bit(dut, bit_index: int, max_cycles: int, name: str):
    for _ in range(max_cycles):
        if led_bit_is_high(dut, bit_index):
            return
        await RisingEdge(dut.clk_100)
    raise TimeoutError(f"Timed out waiting for {name}")


async def send_uart_byte(dut, value: int):
    dut.uart_rxd.value = 0
    await ClockCycles(dut.clk_100, UART_BIT_CYCLES)

    for bit_index in range(8):
        dut.uart_rxd.value = (value >> bit_index) & 1
        await ClockCycles(dut.clk_100, UART_BIT_CYCLES)

    dut.uart_rxd.value = 1
    await ClockCycles(dut.clk_100, UART_BIT_CYCLES)


async def recv_uart_byte(dut) -> int:
    await FallingEdge(dut.uart_txd)
    await ClockCycles(dut.clk_100, UART_BIT_CYCLES + (UART_BIT_CYCLES // 2))

    value = 0
    for bit_index in range(8):
        value |= int(dut.uart_txd.value) << bit_index
        await ClockCycles(dut.clk_100, UART_BIT_CYCLES)

    assert int(dut.uart_txd.value) == 1, "UART TX stop bit was not high"
    return value


async def recv_jpeg_until_eoi(dut, max_bytes: int):
    payload = bytearray()
    while len(payload) < max_bytes:
        payload.append(await recv_uart_byte(dut))
        if len(payload) % 4096 == 0:
            dut._log.info("Received %d JPEG bytes over UART", len(payload))
        if len(payload) >= 2 and payload[-2:] == b"\xff\xd9":
            return bytes(payload)
    raise TimeoutError("Timed out waiting for JPEG EOI marker")


async def send_uart_bytes(dut, payload: bytes):
    for index, value in enumerate(payload):
        if index and index % 4096 == 0:
            dut._log.info("Sent %d/%d UART command bytes", index, len(payload))
        await send_uart_byte(dut, value)


async def wait_uart_route_idle(dut):
    await ClockCycles(dut.clk_100, UART_BIT_CYCLES * (UART_IDLE_TIMEOUT_BITS + 8))


async def wait_uart_mode(dut, expected: int, max_cycles: int, name: str):
    for _ in range(max_cycles):
        if dut.uart_mode.value.is_resolvable and int(dut.uart_mode.value) == expected:
            return
        await RisingEdge(dut.clk_100)
    current = dut.uart_mode.value if dut.uart_mode.value.is_resolvable else "X"
    raise TimeoutError(f"Timed out waiting for UART mode {name}; current={current}")


async def recv_uart_byte_timeout(dut, what: str) -> int:
    return await with_timeout(recv_uart_byte(dut), 200, "us")


async def uart_axi_write(dut, addr: int, data: int):
    request = (
        bytes([UART_AXI_WRITE])
        + int(addr).to_bytes(4, "little")
        + int(data).to_bytes(4, "little")
    )
    await send_uart_bytes(dut, request)
    status = await recv_uart_byte_timeout(dut, "write response")
    if status != UART_AXI_STATUS_OK:
        raise AssertionError(f"UART AXI write 0x{addr:08x} returned status 0x{status:02x}")


async def uart_axi_read(dut, addr: int) -> int:
    request = bytes([UART_AXI_READ]) + int(addr).to_bytes(4, "little")
    await send_uart_bytes(dut, request)
    status = await recv_uart_byte_timeout(dut, "read status")
    data = bytes([await recv_uart_byte_timeout(dut, "read data") for _ in range(4)])
    if status != UART_AXI_STATUS_OK:
        raise AssertionError(f"UART AXI read 0x{addr:08x} returned status 0x{status:02x}")
    return int.from_bytes(data, "little")


async def wait_uart_status_bit(dut, bit_index: int, expected: int, max_reads: int, name: str):
    for _ in range(max_reads):
        status = await uart_axi_read(dut, STS_ADDR)
        if ((status >> bit_index) & 1) == expected:
            return status
    raise TimeoutError(f"Timed out waiting for STS.{name}={expected}")


async def configure_jpeg_over_uart(dut, width: int, height: int):
    await send_uart_byte(dut, ROUTE_CTRL)
    await wait_uart_mode(dut, 1, UART_BIT_CYCLES * 16, "CTRL")
    await wait_uart_status_bit(dut, STS_RDY_BIT, 1, 2000, "RDY")

    for table_index in range(4):
        await uart_axi_write(dut, CGEN_ADDR, CGEN_TRIGGER | table_index)
        await wait_uart_status_bit(dut, STS_CGB_BIT, 0, 2000, "CGB")

    await uart_axi_write(dut, IMSZ_ADDR, (height << 16) | width)
    await uart_axi_write(dut, SUBS_ADDR, 0)
    await uart_axi_write(dut, CTRL_ADDR, 1)
    dut._log.info("JPEG configured over UART AXI-lite")
    await ClockCycles(dut.clk_100, 32)
    await uart_axi_write(dut, CTRL_ADDR, 0)
    if dut.frame_running.value.is_resolvable and not int(dut.frame_running.value):
        raise AssertionError("Frame framer did not arm after CTRL.START")
    await wait_uart_route_idle(dut)


async def count_encoder_output_backpressure(dut, stop_flag):
    stalled_cycles = 0
    while not stop_flag["done"]:
        await RisingEdge(dut.clk_100)
        if signal_is_high(dut.encoder_tvalid) and not signal_is_high(dut.encoder_tready):
            stalled_cycles += 1
    return stalled_cycles


async def wait_for_top_ready(dut):
    dut.btn.setimmediatevalue(0)
    dut.uart_rxd.setimmediatevalue(1)
    cocotb.start_soon(Clock(dut.clk_12, 83334, units="ps").start())

    await with_timeout(wait_for_high(dut.startup_done, dut.clk_12, 1000, "startup_done"), 1, "ms")
    dut._log.info("FPGA startup done")
    await with_timeout(wait_for_high(dut.mmcm_locked, dut.clk_12, 100000, "mmcm_locked"), 10, "ms")
    dut._log.info("MMCM locked")
    await with_timeout(wait_for_led_bit(dut, 0, 200000, "ready LED"), 20, "ms")
    dut._log.info("Top-level reset released")
    await RisingEdge(dut.clk_100)


async def drive_image_axis(dut, payload: bytes):
    dut.image_tdata.value = Force(0)
    dut.image_tvalid.value = Force(0)
    dut.image_tlast.value = Force(0)

    try:
        for index in range(0, len(payload), 3):
            word = payload[index] | (payload[index + 1] << 8) | (payload[index + 2] << 16)
            is_last = index + 3 >= len(payload)

            dut.image_tdata.value = Force(word)
            dut.image_tlast.value = Force(is_last)
            dut.image_tvalid.value = Force(1)

            while True:
                await RisingEdge(dut.clk_100)
                if signal_is_high(dut.image_tready):
                    break

        dut.image_tvalid.value = Force(0)
        dut.image_tlast.value = Force(0)
        await RisingEdge(dut.clk_100)
    finally:
        dut.image_tdata.value = Release()
        dut.image_tvalid.value = Release()
        dut.image_tlast.value = Release()


def load_expected_payload():
    image_path = Path(os.environ.get("BMP_PATH", "")).resolve()
    expected_width = int(os.environ.get("EXPECTED_WIDTH", "192"))
    expected_height = int(os.environ.get("EXPECTED_HEIGHT", "192"))

    rgb_array = load_bmp_array(image_path)
    height, width, channels = rgb_array.shape
    if channels != 3:
        raise AssertionError(f"Expected an RGB image with 3 channels, got {channels}")
    if (width, height) != (expected_width, expected_height):
        raise AssertionError(
            f"Expected a {expected_width}x{expected_height} BMP, got {width}x{height}"
        )

    payload = pack_ycbcr_pixels(rgb_array)
    if len(payload) != width * height * 3:
        raise AssertionError("Packed AXI payload size does not match the BMP dimensions")

    return payload, expected_width, expected_height


@cocotb.test()
async def test_cmod_jpeg_top_uart_end_to_end(dut):
    output_path = Path(os.environ.get("TOP_OUTPUT_JPEG", "cmod_jpeg_top_uart_cocotb.jpg")).resolve()
    payload, expected_width, expected_height = load_expected_payload()
    await wait_for_top_ready(dut)
    await with_timeout(
        configure_jpeg_over_uart(dut, expected_width, expected_height),
        50,
        "ms",
    )

    stop_backpressure_monitor = {"done": False}
    backpressure_monitor = cocotb.start_soon(
        count_encoder_output_backpressure(dut, stop_backpressure_monitor)
    )
    receiver = cocotb.start_soon(recv_jpeg_until_eoi(dut, max_bytes=512 * 1024))

    await send_uart_byte(dut, ROUTE_DATA)
    dut._log.info("Sent UART data route byte, mode=%s", dut.uart_mode.value)
    await wait_uart_mode(dut, 2, UART_BIT_CYCLES * 16, "DATA")
    dut._log.info("UART data mode selected")
    await ClockCycles(dut.clk_100, UART_BIT_CYCLES * 2)
    await send_uart_bytes(dut, payload)
    dut._log.info("Sent %d pixel payload bytes", len(payload))
    await ClockCycles(dut.clk_100, 128)
    dut._log.info(
        "Data snapshot mode=%s frame_running=%s frame_error=%s uart_axis=%s/%s image=%s/%s data_busy=%s/%s",
        dut.uart_mode.value,
        dut.frame_running.value,
        dut.frame_error.value,
        dut.uart_axis_tvalid.value,
        dut.uart_axis_tready.value,
        dut.image_tvalid.value,
        dut.image_tready.value,
        dut.data_rx_busy.value,
        dut.data_tx_busy.value,
    )

    jpeg_bytes = await with_timeout(receiver, 200, "ms")
    stop_backpressure_monitor["done"] = True
    await RisingEdge(dut.clk_100)
    stalled_cycles = await backpressure_monitor

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(jpeg_bytes)

    jpeg_width, jpeg_height = parse_jpeg_dimensions(jpeg_bytes)
    if (jpeg_width, jpeg_height) != (expected_width, expected_height):
        raise AssertionError(
            f"JPEG dimensions {jpeg_width}x{jpeg_height} do not match {expected_width}x{expected_height}"
        )

    if stalled_cycles == 0:
        raise AssertionError("UART TX path did not backpressure the encoder output")

    dut._log.info(
        "Wrote %d JPEG bytes to %s after %d encoder output backpressure cycles",
        len(jpeg_bytes),
        output_path,
        stalled_cycles,
    )
