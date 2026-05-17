package TestJPEGBitAccuracy;

import StmtFSM :: *;
import GetPut :: *;
import Connectable :: *;
import Clocks :: *;

import BlueAXI :: *;
import BlueCSR :: *;
import AXI4_Lite_Test :: *;
import BlueJPEGTestHelper :: *;

import BDPI :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;
import BlueJPEG :: *;
import BlueJPEGRegs :: *;
import RGB2YCbCr :: *;

String input_image_path = "../../../assets/sample_192x192.bmp";

typedef 192 InputWidth;
typedef 192 InputHeight;

typedef 32 WordWidth;

typedef 2560 MaxImgWidth;
typedef 12   DCTScale;
typedef 12   QuantScale;
typedef 16   DPw;


module [Module] mkTestJPEGBitAccuracy(TestHandler);

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

    // ---- clocks ----
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
    BlueJPEG_ifc dut <- mkBlueJPEG(jpeg_cfg);
    let csr_defs <- build_blue_csr_tb_lookup(blue_jpeg_csrs);

    // ---- AXI-Lite master for DUT configuration ----
    AXI4_Lite_Master_Rd#(32, 32) cfg_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) cfg_wr <- mkAXI4_Lite_Master_Wr(16);
    let i_cfg_acc <- mkBlueCSRTbAccessorAXI4Lite(csr_defs, cfg_rd, cfg_wr);

    // ---- AXI-Stream: pixel input (24-bit) ----
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
    Reg#(UInt#(32)) rg_ref_bytes    <- mkReg(0);

    // SimRAM layout (word-addressed):
    //   [0 .. n_pixels-1]                     : input image pixels
    //   [n_pixels .. n_pixels+500_000-1]      : HW output bytes (one byte per word)
    //   [n_pixels+500_000 .. ]                : SW reference bytes (one byte per word)
    UInt#(64) hw_out_base  = fromInteger(valueOf(n_pixels));
    UInt#(64) ref_out_base = fromInteger(valueOf(n_pixels)) + 500000;

    // ---- sub-FSMs ----

    // Feed pixels from SimRAM into DUT via AXI stream
    Stmt feed_pixels = seq
        rg_pixel_idx <= 0;
        while (rg_pixel_idx < fromInteger(valueOf(n_pixels))) action
            let word <- read_word_SimRAM(rg_ram_ptr, extend(rg_pixel_idx));
            Bit#(24) pixel = truncate(pack(word));
            Bit#(32) ycbcr_raw = rgb2ycbcr_ref(
                unpack(pixel[23:16]),
                unpack(pixel[15:08]),
                unpack(pixel[07:00])
            );
            YCbCr_t pix_ycbcr = YCbCr_t {
                y:  unpack(ycbcr_raw[23:16]),
                cb: unpack(ycbcr_raw[15:08]),
                cr: unpack(ycbcr_raw[07:00])
            };
            let is_last = (rg_pixel_idx == fromInteger(valueOf(n_pixels) - 1));
            axis_tx.pkg.put(AXI4_Stream_Pkg {
                data: pack(pix_ycbcr),
                user: ?,
                keep: unpack(-1),
                dest: 0,
                last: is_last
            });
            rg_pixel_idx <= rg_pixel_idx + 1;
        endaction
    endseq;
    FSM fsm_feed_pixels <- mkFSM(feed_pixels);

    // Collect JPEG output bytes into SimRAM (HW output region)
    Stmt collect_output = seq
        while (!rg_finished) action
            let pkg <- axis_out.pkg.get();
            Bit#(8) b = pkg.data;
            write_word_SimRAM(rg_ram_ptr,
                hw_out_base + extend(rg_out_count),
                unpack(extend(b)));
            rg_out_count <= rg_out_count + 1;
            if (pkg.last) begin
                print_fmt($format("HW: received TLAST, total bytes: %0d", rg_out_count + 1), GREEN);
                rg_finished <= True;
            end
        endaction
    endseq;
    FSM fsm_collect <- mkFSM(collect_output);

    // Poll STATUS register for done bit
    FSM fsm_poll_done <- mkFSM(bjpeg_poll_done(i_cfg_acc, rg_axil_rsp, rg_finished));

    // Wait for default table init
    FSM fsm_wait_ready <- mkFSM(bjpeg_wait_tables_ready(i_cfg_acc, rg_axil_rsp));


    // ---- comparison state ----
    Reg#(UInt#(32)) rg_cmp_idx    <- mkReg(0);
    Reg#(UInt#(32)) rg_mismatch   <- mkReg(0);
    Reg#(Bool)      rg_cmp_pass   <- mkReg(True);

    // ================================================================
    // Main test sequence
    // ================================================================

    Stmt main = seq
        rg_out_count <= 0;
        rg_finished  <= False;
        rg_axil_rsp  <= 0;
        rg_cmp_idx   <= 0;
        rg_mismatch  <= 0;
        rg_cmp_pass  <= True;

        print_fmt($format("=== TestJPEGBitAccuracy start ==="), GREEN);

        // ---- phase 1: create SimRAM and load image ----
        action
            let ram <- create_SimRAM(fromInteger(valueOf(ram_words)), fromInteger(valueof(TDiv#(WordWidth, 8))));
            rg_ram_ptr <= ram;
        endaction
        print_s("Loading image into SimRAM...", YELLOW);
        action
            let img <- create_ImageLoader(input_image_path);
            rg_img_load_ptr <= img;
        endaction
        write_to_mem_interleaved_ImageLoader(rg_img_load_ptr, rg_ram_ptr, 0);
        print_s("Image loaded", GREEN);

        // ---- phase 2: run SW reference encoder ----
        print_s("Running SW reference encoder...", YELLOW);
        action
            // subsampling_mode=1 -> YCBCR_422 (matching HW config below)
            let n <- jpeg_encode_ref(input_image_path, 1, rg_ram_ptr, ref_out_base);
            rg_ref_bytes <= n;
        endaction
        print_fmt($format("SW reference: %0d bytes", rg_ref_bytes), GREEN);

        // ---- phase 3: wait for table init ----
        print_s("Waiting for default table init...", YELLOW);
        fsm_wait_ready.start();
        await(fsm_wait_ready.done());

        // ---- phase 4: generate Huffman codes (4 tables) ----
        print_s("Generating Huffman codes...", YELLOW);
        bjpeg_trigger_codegen(i_cfg_acc, rg_axil_rsp, 0);  // DC_Luma
        bjpeg_trigger_codegen(i_cfg_acc, rg_axil_rsp, 1);  // DC_Chroma
        bjpeg_trigger_codegen(i_cfg_acc, rg_axil_rsp, 2);  // AC_Luma
        bjpeg_trigger_codegen(i_cfg_acc, rg_axil_rsp, 3);  // AC_Chroma
        print_s("Huffman code generation complete", GREEN);

        // ---- phase 5: configure BlueJPEG ----
        print_s("Configuring BlueJPEG...", YELLOW);
        action
            Bit#(16) img_height = fromInteger(valueof(InputHeight));
            Bit#(16) img_width  = fromInteger(valueof(InputWidth));
            i_cfg_acc.write_reg_req("IMSZ", {img_height, img_width});
        endaction
        bjpeg_expect_wr_ok(i_cfg_acc);

        // SUBSAMPLING: 4:2:2 = 1
        i_cfg_acc.write_reg_req("SUBS", 1);
        bjpeg_expect_wr_ok(i_cfg_acc);

        // ---- phase 6: start encoder ----
        print_s("Starting BlueJPEG encoder...", YELLOW);
        action
            let start_bit <- i_cfg_acc.field_bit("CTRL", "START");
            Bit#(32) start_mask = 1 << start_bit;
            i_cfg_acc.write_reg_req("CTRL", start_mask);
        endaction
        bjpeg_expect_wr_ok(i_cfg_acc);

        // ---- phase 7: feed pixels + collect output + poll done ----
        par
            seq fsm_feed_pixels.start(); await(fsm_feed_pixels.done()); endseq
            seq fsm_collect.start();     await(fsm_collect.done());     endseq
            seq fsm_poll_done.start();   await(fsm_poll_done.done());   endseq
        endpar

        print_fmt($format("HW encoding complete, %0d bytes output", rg_out_count), GREEN);

        // ---- phase 8: compare HW vs SW reference ----
        print_s("Comparing HW output against SW reference...", YELLOW);

        // Check byte counts match
        if (rg_out_count != rg_ref_bytes) seq
            print_fmt($format("FAIL: byte count mismatch: HW=%0d, SW=%0d",
                rg_out_count, rg_ref_bytes), RED);
            rg_cmp_pass <= False;
        endseq

        // Byte-by-byte comparison (use min of both counts)
        rg_cmp_idx <= 0;
        while (rg_cmp_idx < rg_out_count && rg_cmp_idx < rg_ref_bytes) seq
            action
                let hw_word  <- read_word_SimRAM(rg_ram_ptr, hw_out_base  + extend(rg_cmp_idx));
                let ref_word <- read_word_SimRAM(rg_ram_ptr, ref_out_base + extend(rg_cmp_idx));
                Bit#(8) hw_byte  = truncate(pack(hw_word));
                Bit#(8) ref_byte = truncate(pack(ref_word));
                if (hw_byte != ref_byte) begin
                    if (rg_mismatch < 10)
                        print_fmt($format("MISMATCH at byte %0d: HW=0x%02x, SW=0x%02x",
                            rg_cmp_idx, hw_byte, ref_byte), RED);
                    rg_mismatch <= rg_mismatch + 1;
                    rg_cmp_pass <= False;
                end
                rg_cmp_idx <= rg_cmp_idx + 1;
            endaction
        endseq

        if (rg_mismatch > 0)
            print_fmt($format("Total mismatches: %0d out of %0d bytes",
                rg_mismatch, rg_out_count), RED);

        if (rg_cmp_pass)
            print_fmt($format("=== TestJPEGBitAccuracy PASSED === (%0d bytes match)", rg_out_count), GREEN);
        else
            print_fmt($format("=== TestJPEGBitAccuracy FAILED ==="), RED);
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
