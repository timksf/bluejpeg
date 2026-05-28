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
    localparam integer LEN_BYTE_INDEX_WIDTH = (LEN_BYTES <= 1) ? 1 : $clog2(LEN_BYTES);
    localparam integer PACK_BYTE_INDEX_WIDTH = (DATA_BYTES <= 1) ? 1 : $clog2(DATA_BYTES);
    localparam [LEN_BYTE_INDEX_WIDTH-1:0] LEN_BYTE_LAST = LEN_BYTES - 1;
    localparam [PACK_BYTE_INDEX_WIDTH-1:0] PACK_BYTE_LAST = DATA_BYTES - 1;

    localparam [1:0]
        STATE_IDLE    = 2'd0,
        STATE_LEN     = 2'd1,
        STATE_PAYLOAD = 2'd2;

    reg [1:0] state;
    reg [LEN_WIDTH-1:0] frame_len;
    reg [LEN_WIDTH-1:0] bytes_remaining;
    reg [LEN_BYTE_INDEX_WIDTH-1:0] len_byte_index;
    reg [PACK_BYTE_INDEX_WIDTH-1:0] pack_byte_index;
    reg [1:0] frame_len_mod3;
    reg [TDATA_WIDTH-1:0] pack_reg;

    reg [LEN_WIDTH-1:0] frame_len_next;
    reg [TDATA_WIDTH-1:0] pack_next;
    reg [1:0] frame_len_mod3_next;
    integer byte_index;

    wire axis_word_ready = !m_axis_tvalid || m_axis_tready;
    wire payload_byte_completes_word = (pack_byte_index == PACK_BYTE_LAST);
    wire payload_byte_ready = !payload_byte_completes_word || axis_word_ready;

    assign s_uart_tready =
        (state == STATE_IDLE) ? axis_word_ready :
        (state == STATE_PAYLOAD) ? payload_byte_ready :
        1'b1;

    function [1:0] byte_mod3;
        input [7:0] value;
        reg [3:0] weighted_sum;
        begin
            weighted_sum =
                (value[0] ? 4'd1 : 4'd0) +
                (value[1] ? 4'd2 : 4'd0) +
                (value[2] ? 4'd1 : 4'd0) +
                (value[3] ? 4'd2 : 4'd0) +
                (value[4] ? 4'd1 : 4'd0) +
                (value[5] ? 4'd2 : 4'd0) +
                (value[6] ? 4'd1 : 4'd0) +
                (value[7] ? 4'd2 : 4'd0);

            case (weighted_sum)
                4'd0, 4'd3, 4'd6, 4'd9, 4'd12: byte_mod3 = 2'd0;
                4'd1, 4'd4, 4'd7, 4'd10:       byte_mod3 = 2'd1;
                default:                         byte_mod3 = 2'd2;
            endcase
        end
    endfunction

    function [1:0] add_mod3;
        input [1:0] lhs;
        input [1:0] rhs;
        reg [2:0] sum;
        begin
            sum = lhs + rhs;
            case (sum)
                3'd0, 3'd3: add_mod3 = 2'd0;
                3'd1, 3'd4: add_mod3 = 2'd1;
                default:    add_mod3 = 2'd2;
            endcase
        end
    endfunction

    function payload_length_aligned;
        input [LEN_WIDTH-1:0] value;
        input [1:0] mod3_value;
        begin
            if (DATA_BYTES <= 1) begin
                payload_length_aligned = 1'b1;
            end else if (DATA_BYTES == 2) begin
                payload_length_aligned = (value[0] == 1'b0);
            end else if (DATA_BYTES == 3) begin
                payload_length_aligned = (mod3_value == 2'd0);
            end else if (DATA_BYTES == 4) begin
                payload_length_aligned = (value[1:0] == 2'b00);
            end else if (DATA_BYTES == 8) begin
                payload_length_aligned = (value[2:0] == 3'b000);
            end else begin
                payload_length_aligned = ((value % DATA_BYTES) == {LEN_WIDTH{1'b0}});
            end
        end
    endfunction

    always @* begin
        frame_len_next = frame_len;
        for (byte_index = 0; byte_index < LEN_BYTES; byte_index = byte_index + 1) begin
            if (len_byte_index == byte_index) begin
                frame_len_next[8 * byte_index +: 8] = s_uart_tdata;
            end
        end

        frame_len_mod3_next = add_mod3(frame_len_mod3, byte_mod3(s_uart_tdata));

        pack_next = pack_reg;
        for (byte_index = 0; byte_index < DATA_BYTES; byte_index = byte_index + 1) begin
            if (pack_byte_index == byte_index) begin
                pack_next[8 * byte_index +: 8] = s_uart_tdata;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            frame_len <= {LEN_WIDTH{1'b0}};
            bytes_remaining <= {LEN_WIDTH{1'b0}};
            len_byte_index <= {LEN_BYTE_INDEX_WIDTH{1'b0}};
            pack_byte_index <= {PACK_BYTE_INDEX_WIDTH{1'b0}};
            frame_len_mod3 <= 2'd0;
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
                        pack_byte_index <= {PACK_BYTE_INDEX_WIDTH{1'b0}};
                        len_byte_index <= {LEN_BYTE_INDEX_WIDTH{1'b0}};
                        frame_len_mod3 <= 2'd0;
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
                        frame_len_mod3 <= frame_len_mod3_next;

                        if (len_byte_index == LEN_BYTE_LAST) begin
                            len_byte_index <= {LEN_BYTE_INDEX_WIDTH{1'b0}};

                            if ((frame_len_next == {LEN_WIDTH{1'b0}}) ||
                                !payload_length_aligned(frame_len_next, frame_len_mod3_next)) begin
                                state <= STATE_IDLE;
                                busy <= 1'b0;
                                length_error <= 1'b1;
                            end else begin
                                state <= STATE_PAYLOAD;
                                bytes_remaining <= frame_len_next;
                                pack_byte_index <= {PACK_BYTE_INDEX_WIDTH{1'b0}};
                                pack_reg <= {TDATA_WIDTH{1'b0}};
                            end
                        end else begin
                            len_byte_index <= len_byte_index + 1'b1;
                        end
                    end

                    STATE_PAYLOAD: begin
                        bytes_remaining <= bytes_remaining - {{(LEN_WIDTH-1){1'b0}}, 1'b1};

                        if (payload_byte_completes_word) begin
                            m_axis_tdata <= pack_next;
                            m_axis_tvalid <= 1'b1;
                            m_axis_tlast <= (bytes_remaining == {{(LEN_WIDTH-1){1'b0}}, 1'b1});
                            pack_reg <= {TDATA_WIDTH{1'b0}};
                            pack_byte_index <= {PACK_BYTE_INDEX_WIDTH{1'b0}};
                        end else begin
                            pack_reg <= pack_next;
                            pack_byte_index <= pack_byte_index + 1'b1;
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
