package BlueJPEGTestHelper;

import GetPut :: *;
import StmtFSM :: *;
import ClientServer :: *;

import BlueCSR :: *;
import BlueAXI :: *;

import BDPI :: *;
import Types :: *;
import PrintUtil :: *;

function Action bjpeg_expect_wr_ok(BlueCSRTbAccessor_ifc#(32) cfg_acc);
    action
        let r <- cfg_acc.write_reg_rsp();
        if(r != CSR_OKAY) begin
            $write("Expected CSR_OKAY but got "); $display(fshow(r));
            $finish;
        end
    endaction
endfunction

//poll STATUS.ready until set (default table initialisation complete).
function Stmt bjpeg_wait_tables_ready(
    BlueCSRTbAccessor_ifc#(32) cfg_acc,
    Reg#(Bit#(32)) rg_rsp);
    return seq
        rg_rsp <= 0;
        while (!unpack(rg_rsp[0])) seq
            cfg_acc.read_reg_req("STS");
            action
                let sts_rsp <- cfg_acc.read_reg_rsp();
                let rdy_bit <- cfg_acc.field_bit("STS", "RDY");
                Bit#(32) sts_data = tpl_1(sts_rsp);
                rg_rsp <= zeroExtend(sts_data[rdy_bit]);
            endaction
        endseq
        print_mod_pre_color_t_s("Tables ready", GREEN);
    endseq;
endfunction

//trigger Huffman codegen for htt_val and wait until STATUS.codegen_busy clears.
function Stmt bjpeg_trigger_codegen(
    BlueCSRTbAccessor_ifc#(32) cfg_acc,
    Reg#(Bit#(32)) rg_rsp,
    Bit#(32) htt_val);
    return seq
        action
            Bit#(32) cgen_start = htt_val | 32'h8000_0000;
            cfg_acc.write_reg_req("CGEN", cgen_start);
        endaction
        action
            let _ <- cfg_acc.write_reg_rsp();
        endaction
        rg_rsp <= 1;
        while (unpack(rg_rsp[0])) seq
            cfg_acc.read_reg_req("STS");
            action
                let sts_rsp <- cfg_acc.read_reg_rsp();
                let cgb_bit <- cfg_acc.field_bit("STS", "CGB");
                Bit#(32) sts_data = tpl_1(sts_rsp);
                rg_rsp <= zeroExtend(sts_data[cgb_bit]);
            endaction
        endseq
    endseq;
endfunction

function Stmt bjpeg_trigger_codegen_all(
    BlueCSRTbAccessor_ifc#(32) cfg_acc,
    Reg#(Bit#(32)) rg_rsp);
    return seq
        bjpeg_trigger_codegen(cfg_acc, rg_rsp, 0);  // DC_Luma
        bjpeg_trigger_codegen(cfg_acc, rg_rsp, 1);  // DC_Chroma
        bjpeg_trigger_codegen(cfg_acc, rg_rsp, 2);  // AC_Luma
        bjpeg_trigger_codegen(cfg_acc, rg_rsp, 3);  // AC_Chroma
    endseq;
endfunction

function Stmt bjpeg_trigger_codegen_luma(
    BlueCSRTbAccessor_ifc#(32) cfg_acc,
    Reg#(Bit#(32)) rg_rsp);
    return seq
        bjpeg_trigger_codegen(cfg_acc, rg_rsp, 0);  // DC_Luma
        bjpeg_trigger_codegen(cfg_acc, rg_rsp, 2);  // AC_Luma
    endseq;
endfunction

function Stmt bjpeg_load_image(
    String image_path,
    Integer ram_words,
    Integer word_bytes,
    Reg#(UInt#(64)) rg_ram_ptr,
    Reg#(UInt#(64)) rg_img_load_ptr);
    return seq
        action
            let ram <- create_SimRAM(fromInteger(ram_words), fromInteger(word_bytes));
            rg_ram_ptr <= ram;
        endaction
        print_mod_pre_color_t_s("Loading image into SimRAM...", YELLOW);
        action
            let img <- create_ImageLoader(image_path);
            rg_img_load_ptr <= img;
        endaction
        write_to_mem_interleaved_ImageLoader(rg_img_load_ptr, rg_ram_ptr, 0);
        print_mod_pre_color_t_s("Image loaded", GREEN);
    endseq;
endfunction

function Stmt bjpeg_configure_image(
    BlueCSRTbAccessor_ifc#(32) cfg_acc,
    Integer image_width,
    Integer image_height,
    Bit#(32) subsampling);
    return seq
        action
            Bit#(16) img_height = fromInteger(image_height);
            Bit#(16) img_width  = fromInteger(image_width);
            cfg_acc.write_reg_req("IMSZ", {img_height, img_width});
        endaction
        bjpeg_expect_wr_ok(cfg_acc);

        cfg_acc.write_reg_req("SUBS", subsampling);
        bjpeg_expect_wr_ok(cfg_acc);
    endseq;
endfunction

function Stmt bjpeg_start_encoder(BlueCSRTbAccessor_ifc#(32) cfg_acc);
    return seq
        action
            let start_bit <- cfg_acc.field_bit("CTRL", "START");
            Bit#(32) start_mask = 1 << start_bit;
            cfg_acc.write_reg_req("CTRL", start_mask);
        endaction
        bjpeg_expect_wr_ok(cfg_acc);
    endseq;
endfunction

//poll STATUS.done until set (or rg_finished already True), then assert rg_finished.
function Stmt bjpeg_poll_done(
    BlueCSRTbAccessor_ifc#(32) cfg_acc,
    Reg#(Bit#(32)) rg_rsp,
    Reg#(Bool) rg_finished);
    return seq
        rg_rsp <= 0;
        while (!unpack(rg_rsp[0])) seq
            cfg_acc.read_reg_req("STS");
            action
                let sts_rsp <- cfg_acc.read_reg_rsp();
                let done_bit <- cfg_acc.field_bit("STS", "DONE");
                Bit#(32) sts_data = tpl_1(sts_rsp);
                rg_rsp <= zeroExtend(sts_data[done_bit]);
            endaction
        endseq
        print_mod_pre_color_t_s("DUT signaled done via STATUS register", GREEN);
        rg_finished <= True;
    endseq;
endfunction

function Stmt bjpeg_print_perf(
    BlueCSRTbAccessor_ifc#(32) cfg_acc,
    Reg#(Bit#(32)) rg_rsp,
    String reg_name,
    String value_format);
    return seq
        cfg_acc.read_reg_req(reg_name);
        action
            let perf_rsp <- cfg_acc.read_reg_rsp();
            rg_rsp <= tpl_1(perf_rsp);
        endaction
        print_mod_pre_color_t_f($format(value_format, rg_rsp), GREEN);
    endseq;
endfunction

function Stmt ycbcr_pix_stmt(
    Integer n_pixels,
    Reg#(UInt#(64)) rg_ram_ptr,
    Reg#(UInt#(32)) rg_pixel_idx,
    AXI4_Stream_Wr#(24, wuser) axis_wr);
    return seq
        rg_pixel_idx <= 0;
        while (rg_pixel_idx < fromInteger(n_pixels)) action
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
            let is_last = (rg_pixel_idx == fromInteger(n_pixels - 1));
            axis_wr.pkg.put(AXI4_Stream_Pkg {
                data: pack(pix_ycbcr),
                user: ?,
                keep: unpack(-1),
                dest: 0,
                last: is_last
            });
            rg_pixel_idx <= rg_pixel_idx + 1;
        endaction
    endseq;
endfunction

function Stmt axis2mm_sim32(
    UInt#(64) base_addr,
    Reg#(UInt#(64)) rg_ram_ptr,
    Reg#(UInt#(32)) rg_out_cnt,
    Reg#(Bool) rg_out_finished,
    AXI4_Stream_Rd#(8, wuser) axis_rd
    );
    return seq
        rg_out_cnt <= 0;
        rg_out_finished <= False;
        while (!rg_out_finished) action
            let pkg <- axis_rd.pkg.get();
            Bit#(8) b = pkg.data;
            write_byte_SimRAM(rg_ram_ptr, base_addr + extend(rg_out_cnt), unpack(extend(b)));
            rg_out_cnt <= rg_out_cnt + 1;
            if (pkg.last) begin
                print_mod_pre_color_t_f($format("Received TLAST, total bytes: %0d", rg_out_cnt + 1), GREEN);
                rg_out_finished <= True;
            end
        endaction
    endseq;
endfunction

function Stmt axis2mm_sim(
    UInt#(64) base_addr,
    Reg#(UInt#(64)) rg_ram_ptr,
    Reg#(UInt#(64)) rg_out_cnt,
    Reg#(Bool) rg_out_finished,
    AXI4_Stream_Rd#(8, wuser) axis_rd
    );
    return seq
        rg_out_cnt <= 0;
        rg_out_finished <= False;
        while (!rg_out_finished) action
            let pkg <- axis_rd.pkg.get();
            Bit#(8) b = pkg.data;
            write_byte_SimRAM(rg_ram_ptr, base_addr + extend(rg_out_cnt), unpack(extend(b)));
            rg_out_cnt <= rg_out_cnt + 1;
            if (pkg.last) begin
                print_mod_pre_color_t_f($format("Received TLAST under backpressure, total bytes: %0d", rg_out_cnt + 1), GREEN);
                rg_out_finished <= True;
            end
        endaction
    endseq;
endfunction

endpackage
