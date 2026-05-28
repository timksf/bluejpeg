`timescale 1ns / 1ps

module uart_axis_bridge #(
    parameter integer CLK_FREQ_HZ = 100000000,
    parameter integer BAUD_RATE = 1000000,
    parameter integer RX_AXIS_TDATA_WIDTH = 24,
    parameter integer TX_AXIS_TDATA_WIDTH = 8,
    parameter integer LEN_WIDTH = 32,
    parameter [7:0] CMD_AXIS_WRITE = 8'h53
) (
    input wire clk,
    input wire rst,
    input wire uart_rxd,
    output wire uart_txd,

    output wire [RX_AXIS_TDATA_WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,
    output wire m_axis_tlast,
    input wire m_axis_tready,

    input wire [TX_AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    input wire s_axis_tlast,
    output wire s_axis_tready,

    output wire uart_rx_framing_error,
    output wire uart_rx_overflow_error,
    output wire uart_cmd_error,
    output wire uart_length_error
);

    wire [7:0] rx_byte_tdata;
    wire rx_byte_tvalid;
    wire rx_byte_tready;

    wire [7:0] tx_byte_tdata;
    wire tx_byte_tvalid;
    wire tx_byte_tready;

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_rx_inst (
        .clk(clk),
        .rst(rst),
        .uart_rxd(uart_rxd),
        .rx_data(rx_byte_tdata),
        .rx_valid(rx_byte_tvalid),
        .rx_ready(rx_byte_tready),
        .framing_error(uart_rx_framing_error),
        .overflow_error(uart_rx_overflow_error)
    );

    uart_axis_rx #(
        .TDATA_WIDTH(RX_AXIS_TDATA_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .CMD_AXIS_WRITE(CMD_AXIS_WRITE)
    ) uart_axis_rx_inst (
        .clk(clk),
        .rst(rst),
        .s_uart_tdata(rx_byte_tdata),
        .s_uart_tvalid(rx_byte_tvalid),
        .s_uart_tready(rx_byte_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready),
        .busy(),
        .unexpected_cmd(uart_cmd_error),
        .length_error(uart_length_error)
    );

    axis_uart_tx #(
        .TDATA_WIDTH(TX_AXIS_TDATA_WIDTH)
    ) axis_uart_tx_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_uart_tdata(tx_byte_tdata),
        .m_uart_tvalid(tx_byte_tvalid),
        .m_uart_tready(tx_byte_tready),
        .busy()
    );

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_tx_inst (
        .clk(clk),
        .rst(rst),
        .tx_data(tx_byte_tdata),
        .tx_valid(tx_byte_tvalid),
        .tx_ready(tx_byte_tready),
        .uart_txd(uart_txd),
        .busy()
    );

endmodule
