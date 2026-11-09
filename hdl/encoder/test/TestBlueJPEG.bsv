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

String input_image_path = "../../../assets/sample_192x192.bmp";
String output_jpeg_path = "../result.jpg";

typedef 192 InputWidth;
typedef 192 InputHeight;

//SimRAM definitions
typedef 32 WordWidth;

//DUT type parameters
typedef 256 MaxImgWidth;
typedef 16  DCTScale;
typedef 16  QuantScale;
typedef 8   PixelWidth;

module [Module] mkTestBlueJPEG(TestHandler_ifc);

    function print_s  = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t1 <- mkTestCase;

    Stmt s = seq
        t1.go();
        while(!t1.done()) action endaction
    endseq;

    FSM i_fsm_test <- mkFSM(s);

    method Action go();
        i_fsm_test.start();
    endmethod

    method Bool done();
        return i_fsm_test.done();
    endmethod

endmodule

module [Module] mkTestCase(TestHandler_ifc)
    provisos(
        NumAlias#(n_pixels, TMul#(InputWidth, InputHeight)),
        NumAlias#(ram_words, 'd3_000_000)
    );

    function print_s  = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    //clocks (same domain in simulation)
    let cur_clk <- exposeCurrentClock;
    let cur_rst <- exposeCurrentReset;

    //DUT: BlueJPEG
    BlueJPEGCfg_t#(MaxImgWidth, DCTScale, QuantScale, PixelWidth) jpeg_cfg =
        BlueJPEGCfg_t {
            slow_clock          : cur_clk,
            slow_reset          : cur_rst,
            _prx_miw            : ?,
            _prx_dsc            : ?,
            _prx_qsc            : ?,
            _prx_pixw           : ?,
            en_tiler            : True,
            double_buffer_tiler : True,
            en_chroma           : True
        };
    BlueJPEG_ifc dut <- mkBlueJPEG(jpeg_cfg);
    let csr_defs <- build_blue_csr_tb_lookup(blue_jpeg_csrs);

    //AXI-Lite master for DUT configuration
    AXI4_Lite_Master_Rd#(32, 32) i_cfg_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_cfg_wr <- mkAXI4_Lite_Master_Wr(16);
    let i_cfg_acc <- mkBlueCSRTbAccessorAXI4Lite(csr_defs, i_cfg_rd, i_cfg_wr);

    //AXI-Stream: pixel input (32-bit)
    AXI4_Stream_Wr#(24, 0) i_axis_tx <- mkAXI4_Stream_Wr(128);

    //AXI-Stream: JPEG byte output (8-bit)
    AXI4_Stream_Rd#(8, 0) i_axis_out <- mkAXI4_Stream_Rd(128);

    //connections
    mkConnection(i_axis_tx.fab,       dut.s_axis);
    mkConnection(dut.m_axis,        i_axis_out.fab);
    mkConnection(dut.s_axi_cfg_rd, i_cfg_rd.fab);
    mkConnection(dut.s_axi_cfg_wr, i_cfg_wr.fab);

    //state
    Reg#(UInt#(64)) rg_ram_ptr      <- mkRegU;
    Reg#(UInt#(64)) rg_img_load_ptr <- mkRegU;
    Reg#(Bit#(32))  rg_axil_rsp     <- mkRegU;
    Reg#(Bool)      rg_finished     <- mkReg(False);
    Reg#(UInt#(32)) rg_out_count    <- mkReg(0);
    Reg#(UInt#(32)) rg_pixel_idx    <- mkReg(0);
    Reg#(File)      rg_out_file     <- mkRegU;

    //output write base address in SimRAM (word-addressed, after input image)
    UInt#(64) out_base_addr = fromInteger(valueOf(n_pixels));

    //sub-FSMs

    //feed pixels from SimRAM into DUT via AXI stream
    //interleaved format: one pixel per 64-bit word, R in low byte
    //truncate to 32 bits -> {0x00, B, G, R} per beat
    Stmt feed_pixels = seq
        rg_pixel_idx <= 0;
        while(rg_pixel_idx < fromInteger(valueOf(n_pixels))) action
            let word <- read_word_SimRAM(rg_ram_ptr, extend(rg_pixel_idx));
            Bit#(24) pixel = truncate(pack(word));
            Bit#(32) ycbcr_raw = rgb2ycbcr_ref(
                unpack(pixel[23:16]),   //r
                unpack(pixel[15:08]),   //g
                unpack(pixel[07:00])    //b
            );
            YCbCr_t pix_ycbcr = YCbCr_t {
                y:  unpack(ycbcr_raw[23:16]),
                cb: unpack(ycbcr_raw[15:08]),
                cr: unpack(ycbcr_raw[07:00])
            };
            let is_last = (rg_pixel_idx == fromInteger(valueOf(n_pixels) - 1));
            i_axis_tx.pkg.put(AXI4_Stream_Pkg {
                data: pack(pix_ycbcr),
                user: ?,
                keep: unpack(-1),
                dest: 0,
                id: 0,
                last: is_last
            });
            rg_pixel_idx <= rg_pixel_idx + 1;
        endaction
    endseq;

    //collect JPEG output bytes to output file and RAM output region
    Stmt collect_output = seq
        action
            let fd <- $fopen(output_jpeg_path, "wb");
            if(fd == InvalidFile) begin
                print_s("ERROR: cannot open output file", RED);
                $finish();
            end
            rg_out_file <= fd;
        endaction
        while(!rg_finished) action
            let pkg <- i_axis_out.pkg.get();
            Bit#(8) b = pkg.data;
            //write to SimRAM
            write_word_SimRAM(rg_ram_ptr, out_base_addr + extend(rg_out_count), unpack(extend(b)));
            //write to file
            $fwrite(rg_out_file, "%c", b);
            rg_out_count <= rg_out_count + 1;
            if(pkg.last) begin
                print_fmt($format("Received TLAST, total bytes: %0d", rg_out_count + 1), GREEN);
                rg_finished <= True;
            end
        endaction
        $fclose(rg_out_file);
    endseq;

    //main test sequence

    Stmt main = seq
        rg_out_count <= 0;
        rg_finished <= False;
        rg_axil_rsp <= 0;

        print_fmt($format("=== TestBlueJPEG start ==="), GREEN);

        //phase 1: create SimRAM and load image
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

        //phase 2: wait for table init
        print_s("Waiting for default table init...", YELLOW);
        bjpeg_wait_tables_ready(i_cfg_acc, rg_axil_rsp);

        //no codegen trigger: STS.RDY covers the code tables generated after reset

        //phase 4: configure BlueJPEG
        print_s("Configuring BlueJPEG...", YELLOW);
        action
            Bit#(16) img_height = fromInteger(valueof(InputHeight));
            Bit#(16) img_width  = fromInteger(valueof(InputWidth));
            i_cfg_acc.write_reg_req("IMSZ", {img_height, img_width});
        endaction
        bjpeg_expect_wr_ok(i_cfg_acc);

        //enable only the frame-done interrupt
        action
            let done_bit <- i_cfg_acc.field_bit("IRQE", "DONE");
            i_cfg_acc.write_reg_req("IRQE", 1 << done_bit);
        endaction
        bjpeg_expect_wr_ok(i_cfg_acc);
        bjpeg_expect(!dut.irq, "irq must stay low before the frame completes");

        //phase 5: start encoder
        print_s("Starting BlueJPEG encoder...", YELLOW);
        action
            let start_bit <- i_cfg_acc.field_bit("CTRL", "START");
            Bit#(32) start_mask = 1 << start_bit;
            i_cfg_acc.write_reg_req("CTRL", start_mask);
        endaction
        bjpeg_expect_wr_ok(i_cfg_acc);

        //phase 6: feed pixels + collect output + poll done
        par
            feed_pixels;
            collect_output;
            bjpeg_poll_done(i_cfg_acc, rg_axil_rsp);
        endpar

        i_cfg_acc.read_reg_req("PERF0");
        action
            let perf0_rsp <- i_cfg_acc.read_reg_rsp();
            rg_axil_rsp <= tpl_1(perf0_rsp);
        endaction
        print_fmt($format("Elapsed Cycles: %0d", rg_axil_rsp), GREEN);
        i_cfg_acc.read_reg_req("PERF1");
        action
            let perf1_rsp <- i_cfg_acc.read_reg_rsp();
            rg_axil_rsp <= tpl_1(perf1_rsp);
        endaction
        print_fmt($format("Processed Pixels: %0d", rg_axil_rsp), GREEN);
        i_cfg_acc.read_reg_req("PERF2");
        action
            let perf2_rsp <- i_cfg_acc.read_reg_rsp();
            if(tpl_1(perf2_rsp) != pack(rg_out_count)) begin
                print_fmt($format("PERF2 byte count %0d does not match %0d received bytes", tpl_1(perf2_rsp), rg_out_count), RED);
                $finish(1);
            end
        endaction

        //frame-done interrupt is pending and clears with W1C
        bjpeg_expect(dut.irq, "irq must be high after the frame completes");
        action
            let done_bit <- i_cfg_acc.field_bit("IRQP", "DONE");
            i_cfg_acc.write_reg_req("IRQP", 1 << done_bit);
        endaction
        bjpeg_expect_wr_ok(i_cfg_acc);
        bjpeg_expect(!dut.irq, "irq must clear after W1C of IRQP.DONE");

        //a rejected start latches IRQP.INV but leaves the line low while INV is disabled
        i_cfg_acc.write_reg_req("IMSZ", 0);
        bjpeg_expect_wr_ok(i_cfg_acc);
        action
            let start_bit <- i_cfg_acc.field_bit("CTRL", "START");
            i_cfg_acc.write_reg_req("CTRL", 1 << start_bit);
        endaction
        bjpeg_expect_wr_ok(i_cfg_acc);
        rg_axil_rsp <= 0;
        while(rg_axil_rsp == 0) seq
            i_cfg_acc.read_reg_req("IRQP");
            action
                let rsp     <- i_cfg_acc.read_reg_rsp();
                let inv_bit <- i_cfg_acc.field_bit("IRQP", "INV");
                rg_axil_rsp <= zeroExtend(tpl_1(rsp)[inv_bit]);
            endaction
        endseq
        bjpeg_expect(!dut.irq, "irq must stay low for a disabled source");
        print_s("Interrupt checks passed", GREEN);

        print_fmt($format("JPEG encoding complete, %0d bytes output", rg_out_count), GREEN);
        print_fmt($format("Output written to %s and SimRAM[%0d..]",
            output_jpeg_path, out_base_addr), GREEN);
        print_fmt($format("=== TestBlueJPEG PASSED ==="), GREEN);
    endseq;

    FSM i_fsm_test <- mkFSM(main);

    method Action go();
        i_fsm_test.start();
    endmethod

    method Bool done();
        return i_fsm_test.done();
    endmethod

endmodule

endpackage
