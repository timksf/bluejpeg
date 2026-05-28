`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 100000000,
    parameter integer BAUD_RATE = 1000000
) (
    input wire clk,
    input wire rst,
    input wire [7:0] tx_data,
    input wire tx_valid,
    output wire tx_ready,
    output reg uart_txd,
    output wire busy
);

    localparam integer RAW_CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer CLKS_PER_BIT = (RAW_CLKS_PER_BIT > 0) ? RAW_CLKS_PER_BIT : 1;

    localparam [1:0]
        STATE_IDLE  = 2'd0,
        STATE_START = 2'd1,
        STATE_DATA  = 2'd2,
        STATE_STOP  = 2'd3;

    reg [1:0] state;
    reg [31:0] bit_timer;
    reg [2:0] bit_index;
    reg [7:0] tx_shift;

    assign tx_ready = (state == STATE_IDLE);
    assign busy = (state != STATE_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            bit_timer <= 32'd0;
            bit_index <= 3'd0;
            tx_shift <= 8'd0;
            uart_txd <= 1'b1;
        end else begin
            case (state)
                STATE_IDLE: begin
                    uart_txd <= 1'b1;
                    bit_timer <= 32'd0;
                    bit_index <= 3'd0;

                    if (tx_valid) begin
                        tx_shift <= tx_data;
                        uart_txd <= 1'b0;
                        state <= STATE_START;
                    end
                end

                STATE_START: begin
                    uart_txd <= 1'b0;
                    if (bit_timer == CLKS_PER_BIT - 1) begin
                        bit_timer <= 32'd0;
                        uart_txd <= tx_shift[0];
                        state <= STATE_DATA;
                    end else begin
                        bit_timer <= bit_timer + 32'd1;
                    end
                end

                STATE_DATA: begin
                    uart_txd <= tx_shift[bit_index];
                    if (bit_timer == CLKS_PER_BIT - 1) begin
                        bit_timer <= 32'd0;

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            uart_txd <= 1'b1;
                            state <= STATE_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                            uart_txd <= tx_shift[bit_index + 3'd1];
                        end
                    end else begin
                        bit_timer <= bit_timer + 32'd1;
                    end
                end

                STATE_STOP: begin
                    uart_txd <= 1'b1;
                    if (bit_timer == CLKS_PER_BIT - 1) begin
                        bit_timer <= 32'd0;
                        state <= STATE_IDLE;
                    end else begin
                        bit_timer <= bit_timer + 32'd1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
