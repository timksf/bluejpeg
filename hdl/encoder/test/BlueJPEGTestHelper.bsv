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
