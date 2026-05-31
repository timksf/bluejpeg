import os
import logging
import struct
from itertools import cycle
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource
from PIL import Image


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
        # cocotbext-axi maps the first queued byte onto tdata[7:0].
        # BlueJPEG unpacks the 24-bit word as {y, cb, cr}, so the stream bytes
        # must be emitted least-significant byte first.
        payload.extend((cr, cb, y))
    return bytes(payload)


def extract_frame_bytes(frame: AxiStreamFrame) -> bytes:
    data = frame.tdata
    if isinstance(data, (bytes, bytearray)):
        return bytes(data)
    return bytes(data)


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


async def wait_for_high(signal, clock, max_cycles: int, name: str):
    for _ in range(max_cycles):
        if int(signal.value):
            return
        await RisingEdge(clock)
    raise TimeoutError(f"Timed out waiting for {name}")


def output_backpressure_pattern():
    return cycle(
        [
            False,
            False,
            False,
            False,
            True,
            True,
            True,
            False,
            True,
            False,
            False,
            True,
            True,
            True,
            True,
            False,
        ]
    )


def resolve_output_path(output_name: str) -> Path:
    output_env = os.environ.get("OUTPUT_JPEG")
    if output_env is None:
        return Path(output_name).resolve()

    output_path = Path(output_env).resolve()
    if output_name == "cmod_jpeg_core_cocotb.jpg":
        return output_path

    return Path(
        os.environ.get("OUTPUT_JPEG_BACKPRESSURE", output_path.with_name(output_name))
    ).resolve()


async def run_cmod_jpeg_core(dut, output_name: str, sink_pause_generator=None):
    image_path = Path(os.environ.get("BMP_PATH", "")).resolve()
    output_path = resolve_output_path(output_name)
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

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.clk_dct, 80, units="ns").start())

    dut.rst.setimmediatevalue(1)
    dut.s_axis_tdata.setimmediatevalue(0)
    dut.s_axis_tvalid.setimmediatevalue(0)
    dut.s_axis_tlast.setimmediatevalue(0)

    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
    source.log.setLevel(logging.WARNING)
    sink.log.setLevel(logging.WARNING)
    sink.set_pause_generator(sink_pause_generator)

    for _ in range(8):
        await RisingEdge(dut.clk)
    dut.rst.value = 0

    await with_timeout(wait_for_high(dut.init_done, dut.clk, 200000, "init_done"), 20, "ms")
    if int(dut.init_error.value):
        raise AssertionError("cmod_jpeg_core asserted init_error during startup")

    await source.send(AxiStreamFrame(payload))
    frame = await with_timeout(sink.recv(), 20, "ms")
    sink.clear_pause_generator()
    jpeg_bytes = extract_frame_bytes(frame)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(jpeg_bytes)

    if len(jpeg_bytes) == 0:
        raise AssertionError("No JPEG bytes were received from the AXI stream")

    jpeg_width, jpeg_height = parse_jpeg_dimensions(jpeg_bytes)
    if (jpeg_width, jpeg_height) != (expected_width, expected_height):
        raise AssertionError(
            f"JPEG dimensions {jpeg_width}x{jpeg_height} do not match {expected_width}x{expected_height}"
        )

    dut._log.info("Wrote %d JPEG bytes to %s", len(jpeg_bytes), output_path)


@cocotb.test()
async def test_cmod_jpeg_core_consecutive_frames(dut):
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

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.clk_dct, 80, units="ns").start())

    dut.rst.setimmediatevalue(1)
    dut.s_axis_tdata.setimmediatevalue(0)
    dut.s_axis_tvalid.setimmediatevalue(0)
    dut.s_axis_tlast.setimmediatevalue(0)

    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
    source.log.setLevel(logging.WARNING)
    sink.log.setLevel(logging.WARNING)

    for _ in range(8):
        await RisingEdge(dut.clk)
    dut.rst.value = 0

    await with_timeout(wait_for_high(dut.init_done, dut.clk, 200000, "init_done"), 20, "ms")
    if int(dut.init_error.value):
        raise AssertionError("cmod_jpeg_core asserted init_error during startup")

    for frame_index in range(2):
        send_timeout = (20, "ms") if frame_index == 0 else (100, "us")
        await with_timeout(source.send(AxiStreamFrame(payload)), *send_timeout)
        frame = await with_timeout(sink.recv(), 20, "ms")
        jpeg_bytes = extract_frame_bytes(frame)

        if len(jpeg_bytes) == 0:
            raise AssertionError(f"No JPEG bytes were received for frame {frame_index + 1}")

        jpeg_width, jpeg_height = parse_jpeg_dimensions(jpeg_bytes)
        if (jpeg_width, jpeg_height) != (expected_width, expected_height):
            raise AssertionError(
                f"Frame {frame_index + 1} JPEG dimensions "
                f"{jpeg_width}x{jpeg_height} do not match {expected_width}x{expected_height}"
            )

        dut._log.info(
            "Received frame %d with %d JPEG bytes",
            frame_index + 1,
            len(jpeg_bytes),
        )


@cocotb.test()
async def test_cmod_jpeg_core(dut):
    await run_cmod_jpeg_core(dut, "cmod_jpeg_core_cocotb.jpg")


@cocotb.test()
async def test_cmod_jpeg_core_output_backpressure(dut):
    await run_cmod_jpeg_core(
        dut,
        "cmod_jpeg_core_backpressure_cocotb.jpg",
        sink_pause_generator=output_backpressure_pattern(),
    )
