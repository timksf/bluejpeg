`timescale 1ns / 1ps

module sync_fifo #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH = 4096
) (
    input wire clk,
    input wire rst,

    input wire [DATA_WIDTH-1:0] s_tdata,
    input wire s_tvalid,
    output wire s_tready,

    output wire [DATA_WIDTH-1:0] m_tdata,
    output wire m_tvalid,
    input wire m_tready
);

    localparam integer ADDR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam integer COUNT_WIDTH = ADDR_WIDTH + 1;
    localparam [COUNT_WIDTH-1:0] DEPTH_VALUE = DEPTH;

    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [COUNT_WIDTH-1:0] count;
    reg [DATA_WIDTH-1:0] out_data;
    reg out_valid;

    wire write_fire = s_tvalid && s_tready;
    wire output_ready = !out_valid || m_tready;
    wire read_fire = output_ready && (count != {COUNT_WIDTH{1'b0}});

    assign s_tready = (count != DEPTH_VALUE);
    assign m_tvalid = out_valid;
    assign m_tdata = out_data;

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            count <= {COUNT_WIDTH{1'b0}};
            out_data <= {DATA_WIDTH{1'b0}};
            out_valid <= 1'b0;
        end else begin
            if (write_fire) begin
                mem[wr_ptr] <= s_tdata;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (read_fire) begin
                out_data <= mem[rd_ptr];
                out_valid <= 1'b1;
                rd_ptr <= rd_ptr + 1'b1;
            end else if (m_tready) begin
                out_valid <= 1'b0;
            end

            case ({write_fire, read_fire})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
