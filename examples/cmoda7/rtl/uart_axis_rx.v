`timescale 1ns / 1ps

module uart_axis_rx #(
    parameter integer TDATA_WIDTH = 24,
    parameter integer LEN_WIDTH = 32,
    parameter [7:0] CMD_AXIS_WRITE = 8'h53
) (
    input wire clk,
    input wire rst,
    input wire [7:0] s_uart_tdata,
    input wire s_uart_tvalid,
    output wire s_uart_tready,
    output reg [TDATA_WIDTH-1:0] m_axis_tdata,
    output reg m_axis_tvalid,
    output reg m_axis_tlast,
    input wire m_axis_tready,
    output reg busy,
    output reg unexpected_cmd,
    output reg length_error
);

    // Host protocol: CMD_AXIS_WRITE, 32-bit little-endian byte count, payload.
    // The payload length must be an integer number of AXI-stream words.
    localparam integer DATA_BYTES = TDATA_WIDTH / 8;
    localparam integer LEN_BYTES = LEN_WIDTH / 8;

    localparam [1:0]
        STATE_IDLE    = 2'd0,
        STATE_LEN     = 2'd1,
        STATE_PAYLOAD = 2'd2;

    reg [1:0] state;
    reg [LEN_WIDTH-1:0] frame_len;
    reg [LEN_WIDTH-1:0] bytes_remaining;
    reg [31:0] len_byte_index;
    reg [31:0] pack_byte_index;
    reg [TDATA_WIDTH-1:0] pack_reg;

    reg [LEN_WIDTH-1:0] frame_len_next;
    reg [TDATA_WIDTH-1:0] pack_next;

    wire axis_word_ready = !m_axis_tvalid || m_axis_tready;
    wire payload_byte_completes_word = (pack_byte_index == DATA_BYTES - 1);
    wire payload_byte_ready = !payload_byte_completes_word || axis_word_ready;

    assign s_uart_tready =
        (state == STATE_IDLE) ? axis_word_ready :
        (state == STATE_PAYLOAD) ? payload_byte_ready :
        1'b1;

    always @* begin
        frame_len_next = frame_len;
        frame_len_next[8 * len_byte_index +: 8] = s_uart_tdata;

        pack_next = pack_reg;
        pack_next[8 * pack_byte_index +: 8] = s_uart_tdata;
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            frame_len <= {LEN_WIDTH{1'b0}};
            bytes_remaining <= {LEN_WIDTH{1'b0}};
            len_byte_index <= 32'd0;
            pack_byte_index <= 32'd0;
            pack_reg <= {TDATA_WIDTH{1'b0}};
            m_axis_tdata <= {TDATA_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            busy <= 1'b0;
            unexpected_cmd <= 1'b0;
            length_error <= 1'b0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
            end

            if (s_uart_tvalid && s_uart_tready) begin
                case (state)
                    STATE_IDLE: begin
                        pack_reg <= {TDATA_WIDTH{1'b0}};
                        pack_byte_index <= 32'd0;
                        len_byte_index <= 32'd0;
                        frame_len <= {LEN_WIDTH{1'b0}};
                        bytes_remaining <= {LEN_WIDTH{1'b0}};
                        busy <= 1'b0;

                        if (s_uart_tdata == CMD_AXIS_WRITE) begin
                            state <= STATE_LEN;
                            busy <= 1'b1;
                        end else begin
                            unexpected_cmd <= 1'b1;
                        end
                    end

                    STATE_LEN: begin
                        frame_len <= frame_len_next;

                        if (len_byte_index == LEN_BYTES - 1) begin
                            len_byte_index <= 32'd0;

                            if ((frame_len_next == {LEN_WIDTH{1'b0}}) ||
                                ((frame_len_next % DATA_BYTES) != {LEN_WIDTH{1'b0}})) begin
                                state <= STATE_IDLE;
                                busy <= 1'b0;
                                length_error <= 1'b1;
                            end else begin
                                state <= STATE_PAYLOAD;
                                bytes_remaining <= frame_len_next;
                                pack_byte_index <= 32'd0;
                                pack_reg <= {TDATA_WIDTH{1'b0}};
                            end
                        end else begin
                            len_byte_index <= len_byte_index + 32'd1;
                        end
                    end

                    STATE_PAYLOAD: begin
                        bytes_remaining <= bytes_remaining - {{(LEN_WIDTH-1){1'b0}}, 1'b1};

                        if (payload_byte_completes_word) begin
                            m_axis_tdata <= pack_next;
                            m_axis_tvalid <= 1'b1;
                            m_axis_tlast <= (bytes_remaining == {{(LEN_WIDTH-1){1'b0}}, 1'b1});
                            pack_reg <= {TDATA_WIDTH{1'b0}};
                            pack_byte_index <= 32'd0;
                        end else begin
                            pack_reg <= pack_next;
                            pack_byte_index <= pack_byte_index + 32'd1;
                        end

                        if (bytes_remaining == {{(LEN_WIDTH-1){1'b0}}, 1'b1}) begin
                            state <= STATE_IDLE;
                            busy <= 1'b0;
                        end
                    end

                    default: begin
                        state <= STATE_IDLE;
                        busy <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
