`timescale 1ns / 1ps


module cmod_jpeg_top #(
    parameter integer UART_BAUD_RATE = 1000000
) (
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
    wire [23:0] image_tdata;
    wire image_tvalid;
    wire image_tlast;
    wire image_tready;
    wire [7:0] encoder_tdata;
    wire encoder_tvalid;
    wire encoder_tlast;
    wire encoder_tready;
    wire init_done;
    wire init_error;
    wire uart_rx_framing_error;
    wire uart_rx_overflow_error;
    wire uart_cmd_error;
    wire uart_length_error;
    wire uart_error;
    reg [1:0] btn_sync;
    reg [2:0] rst_sync;

    // Hold the MMCM in reset until FPGA startup is complete.
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
        .CLKOUT1_DIVIDE(48), //could generate DCT clock directly
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
        // CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
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

    // External MMCM feedback.
    BUFG i_clk_fb_BUFG (
        .I(clk_fb),
        .O(clk_fb_buf)
    );

    // Main system clock.
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

    uart_axis_bridge #(
        .CLK_FREQ_HZ(100000000),
        .BAUD_RATE(UART_BAUD_RATE),
        .RX_AXIS_TDATA_WIDTH(24),
        .TX_AXIS_TDATA_WIDTH(8)
    ) uart_axis_bridge_inst (
        .clk(clk_100),
        .rst(core_rst),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .m_axis_tdata(image_tdata),
        .m_axis_tvalid(image_tvalid),
        .m_axis_tlast(image_tlast),
        .m_axis_tready(image_tready),
        .s_axis_tdata(encoder_tdata),
        .s_axis_tvalid(encoder_tvalid),
        .s_axis_tlast(encoder_tlast),
        .s_axis_tready(encoder_tready),
        .uart_rx_framing_error(uart_rx_framing_error),
        .uart_rx_overflow_error(uart_rx_overflow_error),
        .uart_cmd_error(uart_cmd_error),
        .uart_length_error(uart_length_error)
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
        .init_done(init_done),
        .init_error(init_error)
    );

    assign uart_error = uart_rx_framing_error || uart_rx_overflow_error || uart_cmd_error || uart_length_error;
    assign led[0] = mmcm_locked && init_done;
    assign led[1] = init_error || uart_error;


endmodule
