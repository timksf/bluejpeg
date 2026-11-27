package TbEncoderThroughput;

import ClientServer :: *;
import Clocks :: *;
import Connectable :: *;
import GetPut :: *;
import StmtFSM :: *;

import BlueAXI :: *;
import BlueCSRCore :: *;
import BlueCSRTb :: *;

import BDPI :: *;
import BlueJPEG :: *;
import BlueJPEGRegs :: *;
import BlueJPEGTestHelper :: *;
import TestHelper :: *;
import Types :: *;

import "BDPI" function Action prepare_udp_test_image(String path, Bool full_size);

`ifdef UDP_TEST_1080P
typedef 1920 ThroughputWidth;
typedef 1080 ThroughputHeight;
String source_image = `ASSETS_DIR + "/sample_1920x1280.bmp";
Bool full_size = True;
`else
typedef 192 ThroughputWidth;
typedef 192 ThroughputHeight;
String source_image = `ASSETS_DIR + "/sample_192x192.bmp";
Bool full_size = False;
`endif

module [Module] mkTbEncoderThroughput(TestHandler_ifc);
    let i_test <- mkEncoderThroughput(1, False);
    return i_test;
endmodule

module [Module] mkEncoderThroughput#(Integer dct_divider, Bool shallow_dct)(TestHandler_ifc);
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    Clock dct_clock = clk;
    Reset dct_reset = rst;
    if(dct_divider > 1) begin
        let i_divider <- mkClockDivider(dct_divider);
        dct_clock = i_divider.slowClock;
        let reset_sync <- mkAsyncReset(2, rst, dct_clock);
        dct_reset = reset_sync;
    end
    BlueJPEGCfg_t#(1920, 12, 12, 8) cfg = BlueJPEGCfg_t {
        slow_clock:          dct_clock,
        slow_reset:          dct_reset,
        _prx_miw:            ?,
        _prx_dsc:            ?,
        _prx_qsc:            ?,
        _prx_pixw:           ?,
        en_tiler:            True,
        double_buffer_tiler: True,
        en_chroma:           True,
        shallow_dct:         shallow_dct
    };
    BlueJPEG_ifc i_dut <- mkBlueJPEG(cfg);
    let defs <- build_blue_csr_tb_lookup(blue_jpeg_csrs);
    AXI4_Lite_Master_Rd#(32, 32) i_cfg_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_cfg_wr <- mkAXI4_Lite_Master_Wr(1);
    let i_cfg <- mkBlueCSRTbAccessorAXI4Lite(defs, i_cfg_rd, i_cfg_wr);
    AXI4_Stream_Wr#(24, 0) i_pixels <- mkAXI4_Stream_Wr(16);
    AXI4_Stream_Rd#(8, 0)  i_bytes  <- mkAXI4_Stream_Rd(16);
    mkConnection(i_cfg_rd.fab, i_dut.s_axi_cfg_rd);
    mkConnection(i_cfg_wr.fab, i_dut.s_axi_cfg_wr);
    mkConnection(i_pixels.fab, i_dut.s_axis);
    mkConnection(i_dut.m_axis, i_bytes.fab);

    Integer pixels = valueOf(ThroughputWidth) * valueOf(ThroughputHeight);
    Reg#(UInt#(64)) rg_source      <- mkRegU;
    Reg#(UInt#(64)) rg_reference   <- mkRegU;
    Reg#(UInt#(32)) rg_length      <- mkReg(0);
    Reg#(UInt#(32)) rg_sent        <- mkReg(0);
    Reg#(UInt#(32)) rg_received    <- mkReg(0);
    Reg#(UInt#(32)) rg_cycle       <- mkReg(0);
    Reg#(UInt#(32)) rg_last_output <- mkReg(0);
    Reg#(UInt#(2))  rg_frame       <- mkReg(0);
    Reg#(Bool)      rg_active      <- mkReg(False);
    Reg#(Bool)      rg_output_done <- mkReg(False);
    Reg#(Bit#(32))  rg_rsp         <- mkReg(0);

    rule r_tick (rg_active);
        rg_cycle <= rg_cycle + 1;
    endrule

    rule r_watchdog (rg_active && rg_cycle == 20000000);
        $display("ERROR: throughput timeout, sent=%0d received=%0d", rg_sent, rg_received);
        $finish(1);
    endrule

    rule r_source (rg_active && rg_sent < fromInteger(pixels));
        let rgb <- read_word_SimRAM(rg_source, extend(rg_sent));
        Bit#(32) word = pack(truncate(rgb));
        Bit#(32) pixel = rgb2ycbcr_ref(unpack(word[23:16]), unpack(word[15:8]), unpack(word[7:0]));
        i_pixels.pkg.put(AXI4_Stream_Pkg {
            data: truncate(pixel),
            keep: '1,
            user: 0,
            dest: 0,
            id:   0,
            last: rg_sent == fromInteger(pixels - 1)
        });
        rg_sent <= rg_sent + 1;
    endrule

    rule r_sink (rg_active && !rg_output_done);
        let beat <- i_bytes.pkg.get;
        let expected <- read_word_SimRAM(rg_reference, extend(rg_received));
        if(rg_received >= rg_length || beat.data != truncate(pack(expected)) || beat.last != (rg_received == rg_length - 1)) begin
            $display("ERROR: throughput frame=%0d byte=%0d differs from reference", rg_frame, rg_received);
            $finish(1);
        end
        rg_received <= rg_received + 1;
        if(beat.last) begin
            rg_output_done <= True;
            rg_last_output <= rg_cycle + 1;
        end
    endrule

    Stmt main = seq
        prepare_udp_test_image(source_image, full_size);
        action
            let source <- create_SimRAM(3000000, 4);
            let reference <- create_SimRAM(3000000, 4);
            rg_source <= source;
            rg_reference <= reference;
        endaction
        action
            let image <- create_ImageLoader("udp_test_image.bmp");
            write_to_mem_interleaved_ImageLoader(image, rg_source, 0);
        endaction
        action
            let length <- jpeg_encode_ref("udp_test_image.bmp", 0, rg_reference, 0);
            rg_length <= length;
        endaction
        bjpeg_wait_tables_ready(i_cfg, rg_rsp);
        i_cfg.write_reg_req("IMSZ", {Bit#(16)'(fromInteger(valueOf(ThroughputHeight))), Bit#(16)'(fromInteger(valueOf(ThroughputWidth)))});
        bjpeg_expect_wr_ok(i_cfg);
        repeat(2) seq
            action
                rg_cycle <= 0;
                rg_sent <= 0;
                rg_received <= 0;
                rg_output_done <= False;
                rg_active <= True;
                i_dut.start_frame;
            endaction
            await(rg_output_done && !i_dut.busy);
            rg_active <= False;
            $display("DIRECT_FRAME frame=%0d pixels=%0d bytes=%0d last_output_cycles=%0d busy_cycles=%0d", rg_frame, pixels, rg_received, rg_last_output, rg_cycle);
            i_cfg.read_reg_req("PERF0");
            action
                let response <- i_cfg.read_reg_rsp;
                $display("DIRECT_PERF0 %0d", tpl_1(response));
            endaction
            i_cfg.read_reg_req("PERF4");
            action
                let response <- i_cfg.read_reg_rsp;
                $display("DIRECT_FLUSH %0d", tpl_1(response));
            endaction
            i_cfg.read_reg_req("PERF5");
            action
                let response <- i_cfg.read_reg_rsp;
                $display("DIRECT_TOTAL %0d", tpl_1(response));
                // Allow 5% for strip filling and draining, including the smaller fixture.
                // Four DU metadata credits at main/8 exceed this budget by a wide margin.
                if(tpl_2(response) != CSR_OKAY || tpl_1(response) > fromInteger(3 * pixels * 105 / 100)) begin
                    $display("ERROR: encoder throughput below budget (DCT divider %0d)", dct_divider);
                    $fatal(1);
                end
            endaction
            rg_frame <= rg_frame + 1;
        endseq
        $display("TbEncoderThroughput PASSED (%0dx%0d, DCT clock divider %0d)", valueOf(ThroughputWidth), valueOf(ThroughputHeight), dct_divider);
    endseq;
    FSM i_test <- mkFSM(main);
    method Action go() = i_test.start;
    method Bool done() = i_test.done;
endmodule

endpackage
