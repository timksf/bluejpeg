`timescale 1ns / 1ps

module cmod_jpeg_cfg_snoop(
    input wire clk,
    input wire rst,

    input wire s_axi_cfg_awvalid,
    input wire s_axi_cfg_awready,
    input wire [31:0] s_axi_cfg_awaddr,
    input wire s_axi_cfg_wvalid,
    input wire s_axi_cfg_wready,
    input wire [31:0] s_axi_cfg_wdata,

    output reg [31:0] frame_bytes,
    output reg frame_start
);

    localparam [31:0] CTRL_ADDR = 32'h0000_0004;
    localparam [31:0] IMSZ_ADDR = 32'h0000_000c;

    reg have_aw;
    reg have_w;
    reg [31:0] awaddr_hold;
    reg [31:0] wdata_hold;

    wire aw_hs = s_axi_cfg_awvalid && s_axi_cfg_awready;
    wire w_hs = s_axi_cfg_wvalid && s_axi_cfg_wready;
    wire write_complete = (have_aw || aw_hs) && (have_w || w_hs);
    wire [31:0] wr_addr = aw_hs ? s_axi_cfg_awaddr : awaddr_hold;
    wire [31:0] wr_data = w_hs ? s_axi_cfg_wdata : wdata_hold;
    wire [31:0] pixel_count = wr_data[15:0] * wr_data[31:16];

    always @(posedge clk) begin
        if (rst) begin
            have_aw <= 1'b0;
            have_w <= 1'b0;
            awaddr_hold <= 32'd0;
            wdata_hold <= 32'd0;
            frame_bytes <= 32'd0;
            frame_start <= 1'b0;
        end else begin
            frame_start <= 1'b0;

            if (aw_hs) begin
                have_aw <= 1'b1;
                awaddr_hold <= s_axi_cfg_awaddr;
            end

            if (w_hs) begin
                have_w <= 1'b1;
                wdata_hold <= s_axi_cfg_wdata;
            end

            if (write_complete) begin
                have_aw <= 1'b0;
                have_w <= 1'b0;

                if (wr_addr == IMSZ_ADDR) begin
                    frame_bytes <= pixel_count * 32'd3;
                end

                if (wr_addr == CTRL_ADDR && wr_data[0]) begin
                    frame_start <= 1'b1;
                end
            end
        end
    end

endmodule
