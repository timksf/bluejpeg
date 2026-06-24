`timescale 1ns / 1ps

module cmod_jpeg_core(
    input wire clk,
    input wire clk_dct,
    input wire rst,

    input wire [23:0] s_axis_tdata,
    input wire s_axis_tvalid,
    input wire s_axis_tlast,
    output wire s_axis_tready,

    output wire [7:0] m_axis_tdata,
    output wire m_axis_tvalid,
    output wire m_axis_tlast,
    input wire m_axis_tready,

    output wire s_axi_cfg_arready,
    input wire s_axi_cfg_arvalid,
    input wire [31:0] s_axi_cfg_araddr,
    input wire [2:0] s_axi_cfg_arprot,
    output wire s_axi_cfg_rvalid,
    input wire s_axi_cfg_rready,
    output wire [31:0] s_axi_cfg_rdata,
    output wire [1:0] s_axi_cfg_rresp,
    output wire s_axi_cfg_awready,
    input wire s_axi_cfg_awvalid,
    input wire [31:0] s_axi_cfg_awaddr,
    input wire [2:0] s_axi_cfg_awprot,
    output wire s_axi_cfg_wready,
    input wire s_axi_cfg_wvalid,
    input wire [31:0] s_axi_cfg_wdata,
    input wire [3:0] s_axi_cfg_wstrb,
    output wire s_axi_cfg_bvalid,
    input wire s_axi_cfg_bready,
    output wire [1:0] s_axi_cfg_bresp
);

    wire rstn = ~rst;

    mkMiniJPEGEncoder encoder_inst (
        .clk_dct(clk_dct),
        .aclk(clk),
        .aresetn(rstn),

        .S_AXIS_tready(s_axis_tready),
        .S_AXIS_tvalid(s_axis_tvalid),
        .S_AXIS_tdata(s_axis_tdata),
        .S_AXIS_tkeep(3'b111),
        .S_AXIS_tDest(4'b0000),
        .S_AXIS_tid(8'b0000_0000),
        .S_AXIS_tlast(s_axis_tlast),

        .M_AXIS_tvalid(m_axis_tvalid),
        .M_AXIS_tready(m_axis_tready),
        .M_AXIS_tdata(m_axis_tdata),
        .M_AXIS_tlast(m_axis_tlast),
        .M_AXIS_tkeep(),
        .M_AXIS_tDest(),
        .M_AXIS_tid(),

        .S_AXI_cfg_arready(s_axi_cfg_arready),
        .S_AXI_cfg_arvalid(s_axi_cfg_arvalid),
        .S_AXI_cfg_araddr(s_axi_cfg_araddr),
        .S_AXI_cfg_arprot(s_axi_cfg_arprot),
        .S_AXI_cfg_rvalid(s_axi_cfg_rvalid),
        .S_AXI_cfg_rready(s_axi_cfg_rready),
        .S_AXI_cfg_rdata(s_axi_cfg_rdata),
        .S_AXI_cfg_rresp(s_axi_cfg_rresp),
        .S_AXI_cfg_awready(s_axi_cfg_awready),
        .S_AXI_cfg_awvalid(s_axi_cfg_awvalid),
        .S_AXI_cfg_awaddr(s_axi_cfg_awaddr),
        .S_AXI_cfg_awprot(s_axi_cfg_awprot),
        .S_AXI_cfg_wready(s_axi_cfg_wready),
        .S_AXI_cfg_wvalid(s_axi_cfg_wvalid),
        .S_AXI_cfg_wdata(s_axi_cfg_wdata),
        .S_AXI_cfg_wstrb(s_axi_cfg_wstrb),
        .S_AXI_cfg_bvalid(s_axi_cfg_bvalid),
        .S_AXI_cfg_bready(s_axi_cfg_bready),
        .S_AXI_cfg_bresp(s_axi_cfg_bresp)
    );

endmodule
