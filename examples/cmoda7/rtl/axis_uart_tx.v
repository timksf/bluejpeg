`timescale 1ns / 1ps

module axis_uart_tx #(
    parameter integer TDATA_WIDTH = 8
) (
    input wire clk,
    input wire rst,
    input wire [TDATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    input wire s_axis_tlast,
    output wire s_axis_tready,
    output reg [7:0] m_uart_tdata,
    output reg m_uart_tvalid,
    input wire m_uart_tready,
    output reg busy
);

    localparam integer DATA_BYTES = TDATA_WIDTH / 8;

    localparam [0:0]
        STATE_IDLE = 1'b0,
        STATE_SEND = 1'b1;

    reg state;
    reg [TDATA_WIDTH-1:0] beat_reg;
    reg [31:0] byte_index;

    assign s_axis_tready = (state == STATE_IDLE);

    function [7:0] get_byte;
        input [TDATA_WIDTH-1:0] word;
        input [31:0] index;
        begin
            get_byte = word[8 * index +: 8];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            beat_reg <= {TDATA_WIDTH{1'b0}};
            byte_index <= 32'd0;
            m_uart_tdata <= 8'd0;
            m_uart_tvalid <= 1'b0;
            busy <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    byte_index <= 32'd0;
                    m_uart_tvalid <= 1'b0;
                    busy <= 1'b0;

                    if (s_axis_tvalid) begin
                        beat_reg <= s_axis_tdata;
                        m_uart_tdata <= get_byte(s_axis_tdata, 32'd0);
                        m_uart_tvalid <= 1'b1;
                        busy <= 1'b1;
                        state <= STATE_SEND;
                    end
                end

                STATE_SEND: begin
                    busy <= 1'b1;

                    if (m_uart_tvalid && m_uart_tready) begin
                        if (byte_index == DATA_BYTES - 1) begin
                            byte_index <= 32'd0;
                            m_uart_tvalid <= 1'b0;
                            busy <= 1'b0;
                            state <= STATE_IDLE;
                        end else begin
                            byte_index <= byte_index + 32'd1;
                            m_uart_tdata <= get_byte(beat_reg, byte_index + 32'd1);
                            m_uart_tvalid <= 1'b1;
                        end
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
