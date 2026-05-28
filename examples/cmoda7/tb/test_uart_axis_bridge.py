import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, with_timeout


BIT_CYCLES = int(os.environ.get("UART_BIT_CYCLES", "100"))


async def reset_dut(dut):
    dut.uart_rxd.setimmediatevalue(1)
    dut.rst.setimmediatevalue(1)
    dut.m_axis_tready.setimmediatevalue(1)
    dut.s_axis_tdata.setimmediatevalue(0)
    dut.s_axis_tvalid.setimmediatevalue(0)
    dut.s_axis_tlast.setimmediatevalue(0)

    await ClockCycles(dut.clk, 8)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 4)


async def send_uart_byte(dut, value: int):
    dut.uart_rxd.value = 0
    await ClockCycles(dut.clk, BIT_CYCLES)

    for bit_index in range(8):
        dut.uart_rxd.value = (value >> bit_index) & 1
        await ClockCycles(dut.clk, BIT_CYCLES)

    dut.uart_rxd.value = 1
    await ClockCycles(dut.clk, BIT_CYCLES)


async def recv_uart_byte(dut) -> int:
    await FallingEdge(dut.uart_txd)
    await ClockCycles(dut.clk, BIT_CYCLES + (BIT_CYCLES // 2))

    value = 0
    for bit_index in range(8):
        value |= int(dut.uart_txd.value) << bit_index
        await ClockCycles(dut.clk, BIT_CYCLES)

    assert int(dut.uart_txd.value) == 1, "UART TX stop bit was not high"
    return value


async def collect_axis_words(dut, count: int):
    words = []
    while len(words) < count:
        await RisingEdge(dut.clk)
        if int(dut.m_axis_tvalid.value) and int(dut.m_axis_tready.value):
            words.append((int(dut.m_axis_tdata.value), int(dut.m_axis_tlast.value)))
    return words


async def drive_axis_bytes(dut, payload):
    for index, value in enumerate(payload):
        while not int(dut.s_axis_tready.value):
            await RisingEdge(dut.clk)

        dut.s_axis_tdata.value = value
        dut.s_axis_tlast.value = index == len(payload) - 1
        dut.s_axis_tvalid.value = 1
        await RisingEdge(dut.clk)
        dut.s_axis_tvalid.value = 0
        dut.s_axis_tlast.value = 0
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_uart_rx_command_to_axis_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    payload = bytes([1, 2, 3, 4, 5, 6])
    command = bytes([ord("S")]) + len(payload).to_bytes(4, "little") + payload
    collector = cocotb.start_soon(collect_axis_words(dut, 2))

    for value in command:
        await send_uart_byte(dut, value)

    words = await with_timeout(collector, 2, "ms")
    assert words == [(0x030201, 0), (0x060504, 1)]
    assert int(dut.uart_rx_framing_error.value) == 0
    assert int(dut.uart_rx_overflow_error.value) == 0
    assert int(dut.uart_cmd_error.value) == 0
    assert int(dut.uart_length_error.value) == 0


@cocotb.test()
async def test_axis_stream_to_uart_tx(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    payload = bytes([0xA5, 0x5A, 0xFF])
    receiver = cocotb.start_soon(recv_uart_bytes(dut, len(payload)))
    await RisingEdge(dut.clk)

    await drive_axis_bytes(dut, payload)

    received = await with_timeout(receiver, 2, "ms")
    assert received == list(payload)


async def recv_uart_bytes(dut, count: int):
    values = []
    for _ in range(count):
        values.append(await recv_uart_byte(dut))
    return values
