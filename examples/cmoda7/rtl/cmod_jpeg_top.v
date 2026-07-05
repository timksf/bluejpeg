`timescale 1ns / 1ps


module cmod_jpeg_top (
    input wire clk_12,
    input wire btn,
    input wire uart_rxd,
    output wire uart_txd,
    output wire [1:0] led
);

    wire clk_100;
    wire clk_100_unbuf;
    wire clk_fb;
    wire clk_fb_buf;
    wire clk_dct;
    wire mmcm_locked;
    wire startup_done;
    wire mmcm_rst;
    wire rstn_int;
    wire core_rst;
    wire core_rstn;

    reg [1:0] btn_sync;
    reg [2:0] rst_sync;

    wire ctrl_uart_rxd;
    wire ctrl_uart_txd;
    wire data_uart_rxd;
    wire data_uart_txd;
    wire data_rx_busy;
    wire data_tx_busy;
    wire [1:0] uart_mode;

    wire [7:0] uart_axis_tdata;
    wire uart_axis_tvalid;
    wire uart_axis_tlast;
    wire uart_axis_tready;
    wire image_framer_s_tvalid;
    wire image_framer_s_tlast;
    wire image_framer_s_tready;
    wire [23:0] image_tdata;
    wire image_tvalid;
    wire image_tlast;
    wire image_tready;
    wire [7:0] encoder_tdata;
    wire encoder_tvalid;
    wire encoder_tlast;
    wire encoder_tready;

    wire [31:0] frame_bytes;
    wire frame_start;
    wire frame_running;
    wire frame_error;
    reg [31:0] image_bytes_seen;
    reg image_frame_active;

    wire cfg_arready;
    wire cfg_arvalid;
    wire [31:0] cfg_araddr;
    wire [2:0] cfg_arprot;
    wire cfg_rvalid;
    wire cfg_rready;
    wire [31:0] cfg_rdata;
    wire [1:0] cfg_rresp;
    wire cfg_awready;
    wire cfg_awvalid;
    wire [31:0] cfg_awaddr;
    wire [2:0] cfg_awprot;
    wire cfg_wready;
    wire cfg_wvalid;
    wire [31:0] cfg_wdata;
    wire [3:0] cfg_wstrb;
    wire cfg_bvalid;
    wire cfg_bready;
    wire [1:0] cfg_bresp;

    wire image_byte_fire = uart_axis_tvalid && uart_axis_tready;
    wire image_input_last = image_frame_active && ((image_bytes_seen + 32'd1) >= frame_bytes);

    assign image_framer_s_tvalid = uart_axis_tvalid && image_frame_active;
    assign image_framer_s_tlast = image_input_last;
    assign uart_axis_tready = image_frame_active && image_framer_s_tready;
    assign frame_running = image_frame_active;
    assign frame_error = 1'b0;

    STARTUPE2 i_STARTUPE2 (
        .EOS(startup_done)
    );

    assign mmcm_rst = ~startup_done;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(50.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(83.333),
        .CLKOUT0_DIVIDE_F(6.0),
        .CLKOUT1_DIVIDE(48),
        .CLKOUT2_DIVIDE(1),
        .CLKOUT3_DIVIDE(1),
        .CLKOUT4_DIVIDE(1),
        .CLKOUT5_DIVIDE(1),
        .CLKOUT6_DIVIDE(1),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT2_DUTY_CYCLE(0.5),
        .CLKOUT3_DUTY_CYCLE(0.5),
        .CLKOUT4_DUTY_CYCLE(0.5),
        .CLKOUT5_DUTY_CYCLE(0.5),
        .CLKOUT6_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_PHASE(0.0),
        .CLKOUT2_PHASE(0.0),
        .CLKOUT3_PHASE(0.0),
        .CLKOUT4_PHASE(0.0),
        .CLKOUT5_PHASE(0.0),
        .CLKOUT6_PHASE(0.0),
        .CLKOUT4_CASCADE("FALSE"),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.01),
        .STARTUP_WAIT("FALSE")
    ) i_MMCME2_BASE (
        .RST(mmcm_rst),
        .PWRDWN(1'b0),
        .LOCKED(mmcm_locked),
        .CLKIN1(clk_12),
        .CLKFBIN(clk_fb_buf),
        .CLKOUT0(clk_100_unbuf),
        .CLKFBOUT(clk_fb)
    );

    BUFG i_clk_fb_BUFG (
        .I(clk_fb),
        .O(clk_fb_buf)
    );

    BUFG i_clk100_BUFG (
        .I(clk_100_unbuf),
        .O(clk_100)
    );

    BUFR #(
        .BUFR_DIVIDE("8")
    ) i_clkdiv_dct_BUFR (
        .CE(1'b1),
        .CLR(1'b0),
        .I(clk_100),
        .O(clk_dct)
    );

    assign rstn_int = mmcm_locked && startup_done;

    always @(posedge clk_100 or negedge rstn_int) begin
        if (!rstn_int) begin
            btn_sync <= 2'b00;
            rst_sync <= 3'b111;
        end else begin
            btn_sync <= {btn_sync[0], btn};
            if (btn_sync[1]) begin
                rst_sync <= 3'b111;
            end else begin
                rst_sync <= {rst_sync[1:0], 1'b0};
            end
        end
    end

    assign core_rst = rst_sync[2];
    assign core_rstn = ~core_rst;

    always @(posedge clk_100) begin
        if (core_rst) begin
            image_bytes_seen <= 32'd0;
            image_frame_active <= 1'b0;
        end else if (frame_start) begin
            image_bytes_seen <= 32'd0;
            image_frame_active <= frame_bytes != 32'd0;
        end else if (image_byte_fire && image_input_last) begin
            image_bytes_seen <= 32'd0;
            image_frame_active <= 1'b0;
        end else if (image_byte_fire) begin
            image_bytes_seen <= image_bytes_seen + 32'd1;
        end
    end

    mkCmodUartModeSwitch uart_mode_switch_inst (
        .aclk(clk_100),
        .aresetn(core_rstn),
        .uart_value(uart_rxd),
        .uart_tx(uart_txd),
        .ctrl_tx_ctrl_uart_tx(ctrl_uart_txd),
        .ctrl_rx(ctrl_uart_rxd),
        .data_tx_data_uart_tx(data_uart_txd),
        .data_rx_busy_data_rx_busy(data_rx_busy),
        .data_tx_busy_data_tx_busy(data_tx_busy),
        .data_rx(data_uart_rxd),
        .mode(uart_mode)
    );

    mkCmodUartAxiLiteMaster uart_ctrl_bridge_inst (
        .aclk(clk_100),
        .aresetn(core_rstn),
        .uart_value(ctrl_uart_rxd),
        .uart_tx(ctrl_uart_txd),
        .M_AXI_LITE_arvalid(cfg_arvalid),
        .M_AXI_LITE_arready(cfg_arready),
        .M_AXI_LITE_araddr(cfg_araddr),
        .M_AXI_LITE_arprot(cfg_arprot),
        .M_AXI_LITE_rready(cfg_rready),
        .M_AXI_LITE_rvalid(cfg_rvalid),
        .M_AXI_LITE_rdata(cfg_rdata),
        .M_AXI_LITE_rresp(cfg_rresp),
        .M_AXI_LITE_awready(cfg_awready),
        .M_AXI_LITE_awvalid(cfg_awvalid),
        .M_AXI_LITE_awaddr(cfg_awaddr),
        .M_AXI_LITE_awprot(cfg_awprot),
        .M_AXI_LITE_wready(cfg_wready),
        .M_AXI_LITE_wvalid(cfg_wvalid),
        .M_AXI_LITE_wdata(cfg_wdata),
        .M_AXI_LITE_wstrb(cfg_wstrb),
        .M_AXI_LITE_bvalid(cfg_bvalid),
        .M_AXI_LITE_bready(cfg_bready),
        .M_AXI_LITE_bresp(cfg_bresp)
    );

    mkCmodUartAxisBridge uart_data_bridge_inst (
        .aclk(clk_100),
        .aresetn(core_rstn),
        .uart_value(data_uart_rxd),
        .uart_tx(data_uart_txd),
        .tx_enable_tx_enable(uart_mode == 2'd2),
        .M_AXIS_tvalid(uart_axis_tvalid),
        .M_AXIS_tready(uart_axis_tready),
        .M_AXIS_tdata(uart_axis_tdata),
        .M_AXIS_tlast(uart_axis_tlast),
        .M_AXIS_tuser(),
        .M_AXIS_tkeep(),
        .M_AXIS_tDest(),
        .M_AXIS_tid(),
        .S_AXIS_tready(encoder_tready),
        .S_AXIS_tvalid(encoder_tvalid),
        .S_AXIS_tdata(encoder_tdata),
        .S_AXIS_tuser(1'b0),
        .S_AXIS_tkeep(1'b1),
        .S_AXIS_tDest(4'b0000),
        .S_AXIS_tid(8'b0000_0000),
        .S_AXIS_tlast(encoder_tlast),
        .rx_busy(data_rx_busy),
        .tx_busy(data_tx_busy)
    );

    cmod_jpeg_cfg_snoop cfg_snoop_inst (
        .clk(clk_100),
        .rst(core_rst),
        .s_axi_cfg_awvalid(cfg_awvalid),
        .s_axi_cfg_awready(cfg_awready),
        .s_axi_cfg_awaddr(cfg_awaddr),
        .s_axi_cfg_wvalid(cfg_wvalid),
        .s_axi_cfg_wready(cfg_wready),
        .s_axi_cfg_wdata(cfg_wdata),
        .frame_bytes(frame_bytes),
        .frame_start(frame_start)
    );

    mkCmodAxis8ToAxis24Frame image_framer_inst (
        .aclk(clk_100),
        .aresetn(core_rstn),
        .S_AXIS_tready(image_framer_s_tready),
        .S_AXIS_tvalid(image_framer_s_tvalid),
        .S_AXIS_tdata(uart_axis_tdata),
        .S_AXIS_tuser(1'b0),
        .S_AXIS_tkeep(1'b1),
        .S_AXIS_tDest(4'b0000),
        .S_AXIS_tid(8'b0000_0000),
        .S_AXIS_tlast(image_framer_s_tlast),
        .M_AXIS_tvalid(image_tvalid),
        .M_AXIS_tready(image_tready),
        .M_AXIS_tdata(image_tdata),
        .M_AXIS_tlast(image_tlast),
        .M_AXIS_tuser(),
        .M_AXIS_tkeep(),
        .M_AXIS_tDest(),
        .M_AXIS_tid()
    );

    cmod_jpeg_core jpeg_core_inst (
        .clk(clk_100),
        .clk_dct(clk_dct),
        .rst(core_rst),
        .s_axis_tdata(image_tdata),
        .s_axis_tvalid(image_tvalid),
        .s_axis_tlast(image_tlast),
        .s_axis_tready(image_tready),
        .m_axis_tdata(encoder_tdata),
        .m_axis_tvalid(encoder_tvalid),
        .m_axis_tlast(encoder_tlast),
        .m_axis_tready(encoder_tready),
        .s_axi_cfg_arready(cfg_arready),
        .s_axi_cfg_arvalid(cfg_arvalid),
        .s_axi_cfg_araddr(cfg_araddr),
        .s_axi_cfg_arprot(cfg_arprot),
        .s_axi_cfg_rvalid(cfg_rvalid),
        .s_axi_cfg_rready(cfg_rready),
        .s_axi_cfg_rdata(cfg_rdata),
        .s_axi_cfg_rresp(cfg_rresp),
        .s_axi_cfg_awready(cfg_awready),
        .s_axi_cfg_awvalid(cfg_awvalid),
        .s_axi_cfg_awaddr(cfg_awaddr),
        .s_axi_cfg_awprot(cfg_awprot),
        .s_axi_cfg_wready(cfg_wready),
        .s_axi_cfg_wvalid(cfg_wvalid),
        .s_axi_cfg_wdata(cfg_wdata),
        .s_axi_cfg_wstrb(cfg_wstrb),
        .s_axi_cfg_bvalid(cfg_bvalid),
        .s_axi_cfg_bready(cfg_bready),
        .s_axi_cfg_bresp(cfg_bresp)
    );

    assign led[0] = mmcm_locked && !core_rst;
    assign led[1] = frame_error || (uart_mode == 2'd1);

endmodule
