package TestBlueJPEGGrayConsecutive;

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

String input_image_path = "../../../assets/sample_192x192.bmp";
String output_jpeg_path = "../result_gray_consecutive.jpg";

typedef 192 InputWidth;
typedef 192 InputHeight;
typedef 32 WordWidth;

typedef 2560 MaxImgWidth;
typedef 16 DCTScale;
typedef 16 QuantScale;
typedef 16 DPw;

module [Module] mkTestBlueJPEGGrayConsecutive(TestHandler);

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

    let cur_clk <- exposeCurrentClock;
    let cur_rst <- exposeCurrentReset;

    BlueJPEGCfg_t#(MaxImgWidth, DCTScale, QuantScale, DPw) jpeg_cfg =
        BlueJPEGCfg_t {
            slow_clock : cur_clk,
            slow_reset : cur_rst,
            _prx_miw   : ?,
            _prx_dsc   : ?,
            _prx_qsc   : ?,
            _prx_dpw   : ?,
            en_tiler   : True,
            en_chroma  : False
        };
    BlueJPEG_ifc dut <- mkBlueJPEG(jpeg_cfg);
    let csr_defs <- build_blue_csr_tb_lookup(blue_jpeg_csrs);

    AXI4_Lite_Master_Rd#(32, 32) cfg_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) cfg_wr <- mkAXI4_Lite_Master_Wr(16);
    let i_cfg_acc <- mkBlueCSRTbAccessorAXI4Lite(csr_defs, cfg_rd, cfg_wr);

    AXI4_Stream_Wr#(24, 0) axis_tx <- mkAXI4_Stream_Wr(128);
    AXI4_Stream_Rd#(8, 0) axis_out <- mkAXI4_Stream_Rd(128);

    mkConnection(axis_tx.fab,      dut.s_axis);
    mkConnection(dut.m_axis,       axis_out.fab);
    mkConnection(dut.s_axi_cfg_rd, cfg_rd.fab);
    mkConnection(dut.s_axi_cfg_wr, cfg_wr.fab);

    Reg#(UInt#(64)) rg_ram_ptr      <- mkRegU;
    Reg#(UInt#(64)) rg_img_load_ptr <- mkRegU;
    Reg#(Bit#(32))  rg_axil_rsp     <- mkRegU;
    Reg#(Bool)      rg_finished     <- mkReg(False);
    Reg#(UInt#(32)) rg_out_count    <- mkReg(0);
    Reg#(UInt#(32)) rg_total_count  <- mkReg(0);
    Reg#(UInt#(32)) rg_pixel_idx    <- mkReg(0);
    Reg#(UInt#(32)) rg_frame_idx    <- mkReg(0);
    Reg#(UInt#(32)) rg_watchdog     <- mkReg(0);
    Reg#(Bool)      rg_watchdog_en  <- mkReg(False);

    UInt#(64) out_base_addr =
        fromInteger(valueOf(n_pixels)) * fromInteger(valueOf(TDiv#(WordWidth, 8)));

    rule watchdog if (rg_watchdog_en);
        if (rg_watchdog > 2_000_000) begin
            print_fmt($format("ERROR: frame %0d timed out after %0d cycles",
                rg_frame_idx + 1, rg_watchdog), RED);
            $finish();
        end
        rg_watchdog <= rg_watchdog + 1;
    endrule

    Stmt feed_pixels    = ycbcr_pix_stmt(valueof(n_pixels), rg_ram_ptr, rg_pixel_idx, axis_tx);
    Stmt collect_output = seq
        while (!rg_finished) action
            let pkg <- axis_out.pkg.get();
            Bit#(8) b = pkg.data;
            write_byte_SimRAM(
                rg_ram_ptr,
                out_base_addr + extend(rg_total_count),
                unpack(extend(b))
            );
            rg_out_count <= rg_out_count + 1;
            rg_total_count <= rg_total_count + 1;
            if (pkg.last) begin
                print_fmt($format("Frame %0d TLAST, bytes: %0d", rg_frame_idx + 1, rg_out_count + 1), GREEN);
                rg_finished <= True;
            end
        endaction
    endseq;
    FSM fsm_feed_pixels <- mkFSM(feed_pixels);
    FSM fsm_collect     <- mkFSM(collect_output);
    FSM fsm_wait_ready  <- mkFSM(bjpeg_wait_tables_ready(i_cfg_acc, rg_axil_rsp));

    Stmt start_frame = seq
        bjpeg_start_encoder(i_cfg_acc);
        await(dut.s_axis.tready());
    endseq;
    FSM fsm_start_frame <- mkFSM(start_frame);

    Stmt main = seq
        rg_out_count <= 0;
        rg_total_count <= 0;
        rg_finished <= False;
        rg_axil_rsp <= 0;
        rg_watchdog <= 0;
        rg_watchdog_en <= False;

        print_fmt($format("=== TestBlueJPEGGrayConsecutive start ==="), GREEN);

        bjpeg_load_image(
            input_image_path,
            valueof(ram_words),
            valueof(TDiv#(WordWidth, 8)),
            rg_ram_ptr,
            rg_img_load_ptr);

        print_s("Waiting for default table init...", YELLOW);
        fsm_wait_ready.start();
        await(fsm_wait_ready.done());

        print_s("Generating luma Huffman codes...", YELLOW);
        bjpeg_trigger_codegen_luma(i_cfg_acc, rg_axil_rsp);
        print_s("Luma Huffman code generation complete", GREEN);

        print_s("Configuring grayscale mode...", YELLOW);
        bjpeg_configure_image(i_cfg_acc, valueof(InputWidth), valueof(InputHeight), 0);

        for (rg_frame_idx <= 0; rg_frame_idx < 2; rg_frame_idx <= rg_frame_idx + 1) seq
            action
                rg_out_count <= 0;
                rg_finished <= False;
                rg_watchdog <= 0;
                rg_watchdog_en <= True;
            endaction

            print_fmt($format("Starting frame %0d", rg_frame_idx + 1), YELLOW);
            fsm_start_frame.start();
            await(fsm_start_frame.done());
            print_fmt($format("Frame %0d accepted START and exposed input ready", rg_frame_idx + 1), YELLOW);

            par
                seq fsm_feed_pixels.start(); await(fsm_feed_pixels.done()); endseq
                seq fsm_collect.start();     await(fsm_collect.done());     endseq
            endpar

            action
                rg_watchdog_en <= False;
                if (rg_out_count == 0) begin
                    print_fmt($format("ERROR: frame %0d produced no bytes",
                        rg_frame_idx + 1), RED);
                    $finish();
                end
            endaction
        endseq

        dump_range_SimRAM(rg_ram_ptr, output_jpeg_path, out_base_addr, extend(rg_total_count));

        print_fmt($format("Two consecutive grayscale JPEG frames complete, total bytes: %0d", rg_total_count), GREEN);
        print_fmt($format("Output written to %s and SimRAM byte[%0d..]", output_jpeg_path, out_base_addr), GREEN);
        print_fmt($format("=== TestBlueJPEGGrayConsecutive PASSED ==="), GREEN);
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
