`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 100000000,
    parameter integer BAUD_RATE = 1000000
) (
    input wire clk,
    input wire rst,
    input wire uart_rxd,
    output reg [7:0] rx_data,
    output reg rx_valid,
    input wire rx_ready,
    output reg framing_error,
    output reg overflow_error
);

    localparam integer RAW_CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer CLKS_PER_BIT = (RAW_CLKS_PER_BIT > 0) ? RAW_CLKS_PER_BIT : 1;
    localparam integer RAW_START_SAMPLE_TICKS = CLKS_PER_BIT / 2;
    localparam integer START_SAMPLE_TICKS = (RAW_START_SAMPLE_TICKS > 0) ? RAW_START_SAMPLE_TICKS : 1;

    localparam [1:0]
        STATE_IDLE  = 2'd0,
        STATE_START = 2'd1,
        STATE_DATA  = 2'd2,
        STATE_STOP  = 2'd3;

    reg [1:0] state;
    reg [31:0] bit_timer;
    reg [2:0] bit_index;
    reg [7:0] rx_shift;
    reg [1:0] rxd_sync;

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            bit_timer <= 32'd0;
            bit_index <= 3'd0;
            rx_shift <= 8'd0;
            rxd_sync <= 2'b11;
            rx_data <= 8'd0;
            rx_valid <= 1'b0;
            framing_error <= 1'b0;
            overflow_error <= 1'b0;
        end else begin
            rxd_sync <= {rxd_sync[0], uart_rxd};

            if (rx_valid && rx_ready) begin
                rx_valid <= 1'b0;
            end

            case (state)
                STATE_IDLE: begin
                    bit_timer <= 32'd0;
                    bit_index <= 3'd0;

                    if (!rxd_sync[1]) begin
                        state <= STATE_START;
                    end
                end

                STATE_START: begin
                    if (bit_timer == START_SAMPLE_TICKS - 1) begin
                        bit_timer <= 32'd0;
                        if (!rxd_sync[1]) begin
                            state <= STATE_DATA;
                        end else begin
                            state <= STATE_IDLE;
                        end
                    end else begin
                        bit_timer <= bit_timer + 32'd1;
                    end
                end

                STATE_DATA: begin
                    if (bit_timer == CLKS_PER_BIT - 1) begin
                        bit_timer <= 32'd0;
                        rx_shift[bit_index] <= rxd_sync[1];

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state <= STATE_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end else begin
                        bit_timer <= bit_timer + 32'd1;
                    end
                end

                STATE_STOP: begin
                    if (bit_timer == CLKS_PER_BIT - 1) begin
                        bit_timer <= 32'd0;
                        state <= STATE_IDLE;

                        if (!rxd_sync[1]) begin
                            framing_error <= 1'b1;
                        end else if (!rx_valid || rx_ready) begin
                            rx_data <= rx_shift;
                            rx_valid <= 1'b1;
                        end else begin
                            overflow_error <= 1'b1;
                        end
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
