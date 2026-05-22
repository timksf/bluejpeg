`timescale 1ns / 1ps

module cmod_jpeg_core(
    input wire clk,
    input wire rst,
    input wire [23:0] s_axis_tdata,
    input wire s_axis_tvalid,
    input wire s_axis_tlast,
    output wire s_axis_tready,
    output wire [7:0] m_axis_tdata,
    output wire m_axis_tvalid,
    output wire m_axis_tlast,
    input wire m_axis_tready,
    output reg init_done,
    output reg init_error
);

    wire rstn;

    localparam [31:0] CTRL_ADDR = 32'h0000_0004;
    localparam [31:0] STS_ADDR  = 32'h0000_0008;
    localparam [31:0] IMSZ_ADDR = 32'h0000_000c;
    localparam [31:0] SUBS_ADDR = 32'h0000_0010;
    localparam [31:0] CGEN_ADDR = 32'h0000_0014;

    localparam [31:0] IMSZ_192X192 = {16'd192, 16'd192};
    localparam [31:0] SUBS_444     = 32'h0000_0000;
    localparam [31:0] START_ASSERT = 32'h0000_0001;
    localparam [31:0] START_CLEAR  = 32'h0000_0000;
    localparam [31:0] CGEN_TRIGGER = 32'h8000_0000;

    localparam [1:0] AXI_RESP_OKAY = 2'b00;

    localparam integer STS_RDY_BIT = 0;
    localparam integer STS_CGB_BIT = 1;

    localparam [3:0]
        CFG_WAIT_READY   = 4'd0,
        CFG_CODEGEN      = 4'd1,
        CFG_POLL_CODEGEN = 4'd2,
        CFG_WRITE_IMSZ   = 4'd3,
        CFG_WRITE_SUBS   = 4'd4,
        CFG_WRITE_START  = 4'd5,
        CFG_WAIT_AXIS    = 4'd6,
        CFG_CLEAR_START  = 4'd7,
        CFG_READY        = 4'd8,
        CFG_ERROR        = 4'd9;

    reg [3:0] cfg_state;
    reg [1:0] codegen_table;
    reg op_active;
    reg op_is_write;

    reg cfg_awvalid;
    reg [31:0] cfg_awaddr;
    reg [2:0] cfg_awprot;
    reg cfg_wvalid;
    reg [31:0] cfg_wdata;
    reg [3:0] cfg_wstrb;
    reg cfg_bready;

    reg cfg_arvalid;
    reg [31:0] cfg_araddr;
    reg [2:0] cfg_arprot;
    reg cfg_rready;

    wire encoder_s_axis_tready;
    wire encoder_m_axis_tvalid;
    wire [7:0] encoder_m_axis_tdata;
    wire encoder_m_axis_tlast;

    wire cfg_arready;
    wire cfg_rvalid;
    wire [31:0] cfg_rdata;
    wire [1:0] cfg_rresp;
    wire cfg_awready;
    wire cfg_wready;
    wire cfg_bvalid;
    wire [1:0] cfg_bresp;

    wire gated_s_axis_tvalid;

    assign rstn = ~rst;
    assign gated_s_axis_tvalid = init_done ? s_axis_tvalid : 1'b0;
    assign s_axis_tready = init_done ? encoder_s_axis_tready : 1'b0;
    assign m_axis_tvalid = encoder_m_axis_tvalid;
    assign m_axis_tdata = encoder_m_axis_tdata;
    assign m_axis_tlast = encoder_m_axis_tlast;

    mkMiniJPEGEncoder encoder_inst (
        .clk_dct(clk),
        .aclk(clk),
        .aresetn(rstn),
        .S_AXIS_tready(encoder_s_axis_tready),
        .S_AXIS_tvalid(gated_s_axis_tvalid),
        .S_AXIS_tdata(s_axis_tdata),
        .S_AXIS_tkeep(3'b111),
        .S_AXIS_tDest(4'b0000),
        .S_AXIS_tid(8'b0000_0000),
        .S_AXIS_tlast(s_axis_tlast),
        .M_AXIS_tvalid(encoder_m_axis_tvalid),
        .M_AXIS_tready(m_axis_tready),
        .M_AXIS_tdata(encoder_m_axis_tdata),
        .M_AXIS_tlast(encoder_m_axis_tlast),
        .M_AXIS_tkeep(),
        .M_AXIS_tDest(),
        .M_AXIS_tid(),
        .S_AXI_cfg_arready(cfg_arready),
        .S_AXI_cfg_arvalid(cfg_arvalid),
        .S_AXI_cfg_araddr(cfg_araddr),
        .S_AXI_cfg_arprot(cfg_arprot),
        .S_AXI_cfg_rvalid(cfg_rvalid),
        .S_AXI_cfg_rready(cfg_rready),
        .S_AXI_cfg_rdata(cfg_rdata),
        .S_AXI_cfg_rresp(cfg_rresp),
        .S_AXI_cfg_awready(cfg_awready),
        .S_AXI_cfg_awvalid(cfg_awvalid),
        .S_AXI_cfg_awaddr(cfg_awaddr),
        .S_AXI_cfg_awprot(cfg_awprot),
        .S_AXI_cfg_wready(cfg_wready),
        .S_AXI_cfg_wvalid(cfg_wvalid),
        .S_AXI_cfg_wdata(cfg_wdata),
        .S_AXI_cfg_wstrb(cfg_wstrb),
        .S_AXI_cfg_bvalid(cfg_bvalid),
        .S_AXI_cfg_bready(cfg_bready),
        .S_AXI_cfg_bresp(cfg_bresp)
    );

    always @(posedge clk) begin
        if (rst) begin
            cfg_state <= CFG_WAIT_READY;
            codegen_table <= 2'd0;
            op_active <= 1'b0;
            op_is_write <= 1'b0;
            cfg_awvalid <= 1'b0;
            cfg_awaddr <= 32'd0;
            cfg_awprot <= 3'b000;
            cfg_wvalid <= 1'b0;
            cfg_wdata <= 32'd0;
            cfg_wstrb <= 4'hf;
            cfg_bready <= 1'b0;
            cfg_arvalid <= 1'b0;
            cfg_araddr <= 32'd0;
            cfg_arprot <= 3'b000;
            cfg_rready <= 1'b0;
            init_done <= 1'b0;
            init_error <= 1'b0;
        end else begin
            if (cfg_state != CFG_READY) begin
                init_done <= 1'b0;
            end

            if (cfg_state == CFG_ERROR) begin
                init_error <= 1'b1;
            end

            if (op_active) begin
                if (op_is_write) begin
                    if (cfg_awvalid && cfg_awready) begin
                        cfg_awvalid <= 1'b0;
                    end

                    if (cfg_wvalid && cfg_wready) begin
                        cfg_wvalid <= 1'b0;
                    end

                    if ((cfg_awvalid ? cfg_awready : 1'b1) && (cfg_wvalid ? cfg_wready : 1'b1)) begin
                        cfg_bready <= 1'b1;
                    end

                    if (cfg_bready && cfg_bvalid) begin
                        cfg_bready <= 1'b0;
                        op_active <= 1'b0;

                        if (cfg_bresp != AXI_RESP_OKAY) begin
                            cfg_state <= CFG_ERROR;
                        end else begin
                            case (cfg_state)
                                CFG_CODEGEN: begin
                                    cfg_state <= CFG_POLL_CODEGEN;
                                end
                                CFG_WRITE_IMSZ: begin
                                    cfg_state <= CFG_WRITE_SUBS;
                                end
                                CFG_WRITE_SUBS: begin
                                    cfg_state <= CFG_WRITE_START;
                                end
                                CFG_WRITE_START: begin
                                    cfg_state <= CFG_WAIT_AXIS;
                                end
                                CFG_CLEAR_START: begin
                                    cfg_state <= CFG_READY;
                                    init_done <= 1'b1;
                                end
                                default: begin
                                    cfg_state <= CFG_ERROR;
                                end
                            endcase
                        end
                    end
                end else begin
                    if (cfg_arvalid && cfg_arready) begin
                        cfg_arvalid <= 1'b0;
                        cfg_rready <= 1'b1;
                    end

                    if (cfg_rready && cfg_rvalid) begin
                        cfg_rready <= 1'b0;
                        op_active <= 1'b0;

                        if (cfg_rresp != AXI_RESP_OKAY) begin
                            cfg_state <= CFG_ERROR;
                        end else begin
                            case (cfg_state)
                                CFG_WAIT_READY: begin
                                    if (cfg_rdata[STS_RDY_BIT]) begin
                                        cfg_state <= CFG_CODEGEN;
                                    end
                                end
                                CFG_POLL_CODEGEN: begin
                                    if (!cfg_rdata[STS_CGB_BIT]) begin
                                        if (codegen_table == 2'd3) begin
                                            cfg_state <= CFG_WRITE_IMSZ;
                                        end else begin
                                            codegen_table <= codegen_table + 2'd1;
                                            cfg_state <= CFG_CODEGEN;
                                        end
                                    end
                                end
                                default: begin
                                    cfg_state <= CFG_ERROR;
                                end
                            endcase
                        end
                    end
                end
            end else begin
                case (cfg_state)
                    CFG_WAIT_READY: begin
                        op_active <= 1'b1;
                        op_is_write <= 1'b0;
                        cfg_arvalid <= 1'b1;
                        cfg_araddr <= STS_ADDR;
                        cfg_arprot <= 3'b000;
                    end
                    CFG_CODEGEN: begin
                        op_active <= 1'b1;
                        op_is_write <= 1'b1;
                        cfg_awvalid <= 1'b1;
                        cfg_awaddr <= CGEN_ADDR;
                        cfg_awprot <= 3'b000;
                        cfg_wvalid <= 1'b1;
                        cfg_wdata <= CGEN_TRIGGER | {30'd0, codegen_table};
                        cfg_wstrb <= 4'hf;
                    end
                    CFG_POLL_CODEGEN: begin
                        op_active <= 1'b1;
                        op_is_write <= 1'b0;
                        cfg_arvalid <= 1'b1;
                        cfg_araddr <= STS_ADDR;
                        cfg_arprot <= 3'b000;
                    end
                    CFG_WRITE_IMSZ: begin
                        op_active <= 1'b1;
                        op_is_write <= 1'b1;
                        cfg_awvalid <= 1'b1;
                        cfg_awaddr <= IMSZ_ADDR;
                        cfg_awprot <= 3'b000;
                        cfg_wvalid <= 1'b1;
                        cfg_wdata <= IMSZ_192X192;
                        cfg_wstrb <= 4'hf;
                    end
                    CFG_WRITE_SUBS: begin
                        op_active <= 1'b1;
                        op_is_write <= 1'b1;
                        cfg_awvalid <= 1'b1;
                        cfg_awaddr <= SUBS_ADDR;
                        cfg_awprot <= 3'b000;
                        cfg_wvalid <= 1'b1;
                        cfg_wdata <= SUBS_444;
                        cfg_wstrb <= 4'hf;
                    end
                    CFG_WRITE_START: begin
                        op_active <= 1'b1;
                        op_is_write <= 1'b1;
                        cfg_awvalid <= 1'b1;
                        cfg_awaddr <= CTRL_ADDR;
                        cfg_awprot <= 3'b000;
                        cfg_wvalid <= 1'b1;
                        cfg_wdata <= START_ASSERT;
                        cfg_wstrb <= 4'hf;
                    end
                    CFG_WAIT_AXIS: begin
                        if (encoder_s_axis_tready) begin
                            cfg_state <= CFG_CLEAR_START;
                        end
                    end
                    CFG_CLEAR_START: begin
                        op_active <= 1'b1;
                        op_is_write <= 1'b1;
                        cfg_awvalid <= 1'b1;
                        cfg_awaddr <= CTRL_ADDR;
                        cfg_awprot <= 3'b000;
                        cfg_wvalid <= 1'b1;
                        cfg_wdata <= START_CLEAR;
                        cfg_wstrb <= 4'hf;
                    end
                    CFG_READY: begin
                        init_done <= 1'b1;
                    end
                    CFG_ERROR: begin
                        init_error <= 1'b1;
                    end
                    default: begin
                        cfg_state <= CFG_ERROR;
                    end
                endcase
            end
        end
    end

endmodule