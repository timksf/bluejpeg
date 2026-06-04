package TestBlueJPEG;

import StmtFSM :: *;
import GetPut :: *;
import Connectable :: *;
import Clocks :: *;

import BlueAXI :: *;
import BlueCSR :: *;
import BlueJPEGTestHelper :: *;

import BDPI :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;
import BlueJPEG :: *;
import BlueJPEGRegs :: *;
import RGB2YCbCr :: *;

String input_image_path = "../../../assets/sample_1920x1280.bmp";
String output_jpeg_path = "../result.jpg";

typedef 1920 InputWidth;
typedef 1280 InputHeight;

//SimRAM definitions
typedef 32 WordWidth;

//DUT type parameters
typedef 2560 MaxImgWidth;
typedef 16  DCTScale;
typedef 16  QuantScale;
typedef 16  DPw;


module [Module] mkTestBlueJPEG(TestHandler);

    function print_s  = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t1 <- test;

    Stmt s = seq
        t1.go();
        while (!t1.done()) action endaction
    endseq;

    FSM fsm_test <- mkFSM(s);

    method Action go();
        fsm_test.start();
    endmethod

    method Bool done();
        return fsm_test.done();
    endmethod

endmodule

module [Module] test(TestHandler)
    provisos(
        NumAlias#(n_pixels, TMul#(InputWidth, InputHeight)),
        NumAlias#(ram_words, 'd3_000_000)
    );

    function print_s  = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    // ---- clocks (same domain in simulation) ----
    let cur_clk <- exposeCurrentClock;
    let cur_rst <- exposeCurrentReset;

    // ---- DUT: BlueJPEG ----
    BlueJPEGCfg_t#(MaxImgWidth, DCTScale, QuantScale, DPw) jpeg_cfg = 
        BlueJPEGCfg_t {
            slow_clock : cur_clk,
            slow_reset : cur_rst,
            _prx_miw   : ?,
            _prx_dsc   : ?,
            _prx_qsc   : ?,
            _prx_dpw   : ?,
            en_tiler   : True,
            en_chroma  : True
        };
    BlueJPEG_ifc dut    <- mkBlueJPEG(jpeg_cfg);
    let csr_defs        <- build_blue_csr_tb_lookup(blue_jpeg_csrs);

    // ---- AXI-Lite master for DUT configuration ----
    AXI4_Lite_Master_Rd#(32, 32) cfg_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) cfg_wr <- mkAXI4_Lite_Master_Wr(16);
    let i_cfg_acc <- mkBlueCSRTbAccessorAXI4Lite(csr_defs, cfg_rd, cfg_wr);

    // ---- AXI-Stream: pixel input (32-bit) ----
    AXI4_Stream_Wr#(24, 0) axis_tx <- mkAXI4_Stream_Wr(128);

    // ---- AXI-Stream: JPEG byte output (8-bit) ----
    AXI4_Stream_Rd#(8, 0) axis_out <- mkAXI4_Stream_Rd(128);

    // ---- connections ----
    mkConnection(axis_tx.fab,       dut.s_axis);
    mkConnection(dut.m_axis,        axis_out.fab);
    mkConnection(dut.s_axi_cfg_rd, cfg_rd.fab);
    mkConnection(dut.s_axi_cfg_wr, cfg_wr.fab);

    // ---- state ----
    Reg#(UInt#(64)) rg_ram_ptr      <- mkRegU;
    Reg#(UInt#(64)) rg_img_load_ptr <- mkRegU;
    Reg#(Bit#(32))  rg_axil_rsp     <- mkRegU;
    Reg#(Bool)      rg_finished     <- mkReg(False);
    Reg#(UInt#(32)) rg_out_count    <- mkReg(0);
    Reg#(UInt#(32)) rg_pixel_idx    <- mkReg(0);

    // output write base address in SimRAM (byte-addressed, after input image)
    UInt#(64) out_base_addr =
        fromInteger(valueOf(n_pixels)) * fromInteger(valueOf(TDiv#(WordWidth, 8)));

    // ---- sub-FSMs ----

    Stmt feed_pixels = ycbcr_pix_stmt(valueof(n_pixels), rg_ram_ptr, rg_pixel_idx, axis_tx);
    FSM fsm_feed_pixels <- mkFSM(feed_pixels);

    Stmt collect_output = axis2mm_sim32(out_base_addr, rg_ram_ptr, rg_out_count, rg_finished, axis_out);
    FSM fsm_collect <- mkFSM(collect_output);

    //poll CTRL register for done bit
    FSM fsm_poll_done <- mkFSM(bjpeg_poll_done(i_cfg_acc, rg_axil_rsp, rg_finished));

    //wait for default table init (poll STATUS.ready)
    FSM fsm_wait_ready <- mkFSM(bjpeg_wait_tables_ready(i_cfg_acc, rg_axil_rsp));


    // ================================================================
    // Main test sequence
    // ================================================================

    Stmt main = seq
        rg_out_count <= 0;
        rg_finished <= False;
        rg_axil_rsp <= 0;

        print_fmt($format("=== TestBlueJPEG start ==="), GREEN);

        // ---- phase 1: create SimRAM and load image ----
        bjpeg_load_image(
            input_image_path,
            valueof(ram_words),
            valueof(TDiv#(WordWidth, 8)),
            rg_ram_ptr,
            rg_img_load_ptr);

        // ---- phase 2: wait for table init ----
        print_s("Waiting for default table init...", YELLOW);
        fsm_wait_ready.start();
        await(fsm_wait_ready.done());

        // ---- phase 3: generate Huffman codes (4 tables) ----
        print_s("Generating Huffman codes...", YELLOW);
        bjpeg_trigger_codegen_all(i_cfg_acc, rg_axil_rsp);
        print_s("Huffman code generation complete", GREEN);

        // ---- phase 4: configure BlueJPEG ----
        print_s("Configuring BlueJPEG...", YELLOW);
        bjpeg_configure_image(i_cfg_acc, valueof(InputWidth), valueof(InputHeight), 0);

        // ---- phase 5: start encoder ----
        print_s("Starting BlueJPEG encoder...", YELLOW);
        bjpeg_start_encoder(i_cfg_acc);

        // ---- phase 6: feed pixels + collect output + poll done ----
        par
            seq fsm_feed_pixels.start(); await(fsm_feed_pixels.done()); endseq
            seq fsm_collect.start();     await(fsm_collect.done());     endseq
            seq fsm_poll_done.start();   await(fsm_poll_done.done());   endseq
        endpar
        dump_range_SimRAM(rg_ram_ptr, output_jpeg_path, out_base_addr, extend(rg_out_count));

        bjpeg_print_perf(i_cfg_acc, rg_axil_rsp, "PERF0", "Elapsed Cycles: %0d");
        bjpeg_print_perf(i_cfg_acc, rg_axil_rsp, "PERF1", "Processed Pixels: %0d");

        print_fmt($format("JPEG encoding complete, %0d bytes output", rg_out_count), GREEN);
        print_fmt($format("Output written to %s and SimRAM byte[%0d..]",
            output_jpeg_path, out_base_addr), GREEN);
        print_fmt($format("=== TestBlueJPEG PASSED ==="), GREEN);
    endseq;

    FSM fsm_test <- mkFSM(main);

    method Action go();
        fsm_test.start();
    endmethod

    method Bool done();
        return fsm_test.done();
    endmethod

endmodule

endpackage
