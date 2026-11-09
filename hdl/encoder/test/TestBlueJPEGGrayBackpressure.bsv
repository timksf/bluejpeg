package TestBlueJPEGGrayBackpressure;

import StmtFSM :: *;
import GetPut :: *;
import Connectable :: *;
import Clocks :: *;
import FIFOF :: *;
import SpecialFIFOs :: *;
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
String output_jpeg_path = "../result_gray_backpressure.jpg";

typedef 192 InputWidth;
typedef 192 InputHeight;

typedef 32 WordWidth;

typedef 2560 MaxImgWidth;
typedef 16 DCTScale;
typedef 16 QuantScale;
typedef 8 PixelWidth;

module mkBackpressuredAXI4StreamRd#(Integer bufferSize)(AXI4_Stream_Rd#(datawidth, userwidth))
    provisos(
        Div#(datawidth, 8, keepwidth)
    );

    let isRst <- isResetAsserted();

    Wire#(Bool)            w_tvalid_in <- mkBypassWire();
    Wire#(Bit#(datawidth)) w_data_in   <- mkBypassWire();
    Wire#(Bit#(userwidth)) w_user_in   <- mkBypassWire();
    Wire#(Bit#(keepwidth)) w_keep_in   <- mkBypassWire();
    Wire#(Bit#(4))         w_dest_in   <- mkBypassWire();
    Wire#(Bit#(8))         w_id_in     <- mkBypassWire();
    Wire#(Bool)            w_last_in   <- mkBypassWire();
    Reg#(UInt#(8))         rg_cycle    <- mkReg(0);

    FIFOF#(AXI4_Stream_Pkg#(datawidth, userwidth)) f_in <- mkSizedFIFOF(bufferSize);
    if(bufferSize == 1)
        f_in <- mkPipelineFIFOF();
    if(bufferSize == 2)
        f_in <- mkFIFOF();

    function Bool ready_pattern();
        UInt#(8) phase = rg_cycle % 16;
        return phase < 5 || phase == 9 || phase == 10 || phase == 15;
    endfunction

    rule r_count_cycles (!isRst);
        rg_cycle <= rg_cycle + 1;
    endrule

    rule r_write_fifo (!isRst && ready_pattern() && w_tvalid_in && f_in.notFull());
        AXI4_Stream_Pkg#(datawidth, userwidth) s;
        s.data = w_data_in;
        s.user = w_user_in;
        s.keep = w_keep_in;
        s.dest = w_dest_in;
        s.id   = w_id_in;
        s.last = w_last_in;
        f_in.enq(s);
    endrule

    interface Get pkg = toGet(f_in);

    interface AXI4_Stream_Rd_Fab fab;
        interface tready = !isRst && ready_pattern() && f_in.notFull();
        interface ptvalid = w_tvalid_in._write;
        interface ptdata  = w_data_in._write;
        interface ptuser  = w_user_in._write;
        interface ptkeep  = w_keep_in._write;
        interface ptDest  = w_dest_in._write;
        interface ptid    = w_id_in._write;
        interface ptlast  = w_last_in._write;
    endinterface
endmodule

module [Module] mkTestBlueJPEGGrayBackpressure(TestHandler_ifc);

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

    let cur_clk <- exposeCurrentClock;
    let cur_rst <- exposeCurrentReset;

    BlueJPEGCfg_t#(MaxImgWidth, DCTScale, QuantScale, PixelWidth) jpeg_cfg =
        BlueJPEGCfg_t {
            slow_clock          : cur_clk,
            slow_reset          : cur_rst,
            _prx_miw            : ?,
            _prx_dsc            : ?,
            _prx_qsc            : ?,
            _prx_pixw           : ?,
            en_tiler            : True,
            double_buffer_tiler : False,
            en_chroma           : False
        };
    BlueJPEG_ifc dut <- mkBlueJPEG(jpeg_cfg);
    let csr_defs <- build_blue_csr_tb_lookup(blue_jpeg_csrs);

    AXI4_Lite_Master_Rd#(32, 32) i_cfg_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) i_cfg_wr <- mkAXI4_Lite_Master_Wr(16);
    let i_cfg_acc <- mkBlueCSRTbAccessorAXI4Lite(csr_defs, i_cfg_rd, i_cfg_wr);

    AXI4_Stream_Wr#(24, 0) i_axis_tx  <- mkAXI4_Stream_Wr(128);
    AXI4_Stream_Rd#(8, 0)  i_axis_out <- mkBackpressuredAXI4StreamRd(8);

    mkConnection(i_axis_tx.fab,      dut.s_axis);
    mkConnection(dut.m_axis,       i_axis_out.fab);
    mkConnection(dut.s_axi_cfg_rd, i_cfg_rd.fab);
    mkConnection(dut.s_axi_cfg_wr, i_cfg_wr.fab);

    Reg#(UInt#(64)) rg_ram_ptr      <- mkRegU;
    Reg#(UInt#(64)) rg_img_load_ptr <- mkRegU;
    Reg#(Bit#(32))  rg_axil_rsp     <- mkRegU;
    Reg#(Bool)      rg_finished     <- mkReg(False);
    Reg#(UInt#(32)) rg_out_count    <- mkReg(0);
    Reg#(UInt#(32)) rg_pixel_idx    <- mkReg(0);
    Reg#(Bit#(8))   rg_prev_byte    <- mkReg(0);
    Reg#(Bit#(8))   rg_last_byte    <- mkReg(0);
    Reg#(File)      rg_out_file     <- mkRegU;

    UInt#(64) out_base_addr = fromInteger(valueOf(n_pixels));

    Stmt feed_pixels = seq
        rg_pixel_idx <= 0;
        while(rg_pixel_idx < fromInteger(valueOf(n_pixels))) action
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
            write_word_SimRAM(rg_ram_ptr, out_base_addr + extend(rg_out_count), unpack(extend(b)));
            $fwrite(rg_out_file, "%c", b);
            rg_prev_byte <= rg_last_byte;
            rg_last_byte <= b;
            rg_out_count <= rg_out_count + 1;
            if(pkg.last) begin
                print_fmt($format("Received TLAST under backpressure, total bytes: %0d", rg_out_count + 1), GREEN);
                rg_finished <= True;
            end
        endaction
        $fclose(rg_out_file);
    endseq;

    Stmt main = seq
        rg_out_count <= 0;
        rg_prev_byte <= 0;
        rg_last_byte <= 0;
        rg_finished <= False;
        rg_axil_rsp <= 0;

        print_fmt($format("=== TestBlueJPEGGrayBackpressure start ==="), GREEN);

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

        print_s("Waiting for default table init...", YELLOW);
        bjpeg_wait_tables_ready(i_cfg_acc, rg_axil_rsp);

        print_s("Generating luma Huffman codes...", YELLOW);
        bjpeg_trigger_codegen(i_cfg_acc, rg_axil_rsp, 0);
        bjpeg_trigger_codegen(i_cfg_acc, rg_axil_rsp, 2);
        print_s("Luma Huffman code generation complete", GREEN);

        print_s("Configuring grayscale mode...", YELLOW);
        action
            Bit#(16) img_height = fromInteger(valueof(InputHeight));
            Bit#(16) img_width  = fromInteger(valueof(InputWidth));
            i_cfg_acc.write_reg_req("IMSZ", {img_height, img_width});
        endaction
        bjpeg_expect_wr_ok(i_cfg_acc);

        print_s("Starting grayscale BlueJPEG encoder with output backpressure...", YELLOW);
        action
            let start_bit <- i_cfg_acc.field_bit("CTRL", "START");
            Bit#(32) start_mask = 1 << start_bit;
            i_cfg_acc.write_reg_req("CTRL", start_mask);
        endaction
        bjpeg_expect_wr_ok(i_cfg_acc);

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

        action
            if(rg_out_count == 0) begin
                print_s("ERROR: no JPEG bytes were produced", RED);
                $finish();
            end
            if(rg_prev_byte != 'hFF || rg_last_byte != 'hD9) begin
                print_fmt($format("ERROR: output does not end with EOI, tail=%02x %02x",
                    rg_prev_byte, rg_last_byte), RED);
                $finish();
            end
        endaction

        print_fmt($format("Backpressured grayscale JPEG complete, %0d bytes output", rg_out_count), GREEN);
        print_fmt($format("Output written to %s and SimRAM[%0d..]", output_jpeg_path, out_base_addr), GREEN);
        print_fmt($format("=== TestBlueJPEGGrayBackpressure PASSED ==="), GREEN);
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
