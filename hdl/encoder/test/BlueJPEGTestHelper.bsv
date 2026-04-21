package BlueJPEGTestHelper;

import StmtFSM :: *;
import BlueAXI :: *;
import BlueJPEG :: *;
import PrintUtil :: *;

//write image dimensions to the IMG_SIZE config register ({height, width}).
function Action bjpeg_cfg_img_size(
    AXI4_Lite_Master_Wr#(32, 32) cfg_wr,
    Bit#(16) width, Bit#(16) height);
    return axi4_lite_write(cfg_wr, fromInteger(cfg_img_size_offs), {height, width});
endfunction

//poll STATUS.ready until set (default table initialisation complete).
function Stmt bjpeg_wait_tables_ready(
    AXI4_Lite_Master_Rd#(32, 32) cfg_rd,
    Reg#(Bit#(32)) rg_rsp);
    return seq
        wait_bit_set(cfg_rd, cfg_status_offs, sts_ready_bit, rg_rsp);
        print_mod_pre_color_t_s("Tables ready", GREEN);
    endseq;
endfunction

//trigger Huffman codegen for htt_val and wait until STATUS.codegen_busy clears.
function Stmt bjpeg_trigger_codegen(
    AXI4_Lite_Master_Wr#(32, 32) cfg_wr,
    AXI4_Lite_Master_Rd#(32, 32) cfg_rd,
    Reg#(Bit#(32)) rg_rsp,
    Bit#(32) htt_val);
    return seq
        axi4_lite_write(cfg_wr, fromInteger(cfg_codegen_offs),
            htt_val | (1 << cg_trigger_bit));
        rg_rsp <= 'hFFFF;
        wait_bit_not_set(cfg_rd, cfg_status_offs, sts_cg_busy_bit, rg_rsp);
    endseq;
endfunction

//poll CTRL.done until set (or rg_finished already True), then assert rg_finished.
function Stmt bjpeg_poll_done(
    AXI4_Lite_Master_Rd#(32, 32) cfg_rd,
    Reg#(Bit#(32)) rg_rsp,
    Reg#(Bool) rg_finished);
    return seq
        wait_bit_set(cfg_rd, cfg_ctrl_offs, ctrl_done_bit, rg_rsp);
        print_mod_pre_color_t_s("DUT signaled done via CTRL register", GREEN);
        rg_finished <= True;
    endseq;
endfunction

endpackage
