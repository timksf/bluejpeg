package BlueJPEGTestHelper;

import StmtFSM :: *;
import BlueCSRCore :: *;
import BlueCSRTb :: *;

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

function Action bjpeg_expect(Bool cond, String msg);
    action
        if(!cond) begin
            print_mod_pre_color_t_s(msg, RED);
            $finish(1);
        end
    endaction
endfunction

//poll STATUS.ready until set (default table initialisation complete)
function Stmt bjpeg_wait_tables_ready(
    BlueCSRTbAccessor_ifc#(32) cfg_acc,
    Reg#(Bit#(32)) rg_rsp);
    return seq
        rg_rsp <= 0;
        while(!unpack(rg_rsp[0])) seq
            cfg_acc.read_reg_req("STS");
            action
                let      sts_rsp  <- cfg_acc.read_reg_rsp();
                let      rdy_bit  <- cfg_acc.field_bit("STS", "RDY");
                Bit#(32) sts_data = tpl_1(sts_rsp);
                rg_rsp <= zeroExtend(sts_data[rdy_bit]);
            endaction
        endseq
        print_mod_pre_color_t_s("Tables ready", GREEN);
    endseq;
endfunction

//trigger Huffman codegen for htt_val and wait until STATUS.codegen_busy clears
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
        while(unpack(rg_rsp[0])) seq
            cfg_acc.read_reg_req("STS");
            action
                let      sts_rsp  <- cfg_acc.read_reg_rsp();
                let      cgb_bit  <- cfg_acc.field_bit("STS", "CGB");
                Bit#(32) sts_data = tpl_1(sts_rsp);
                rg_rsp <= zeroExtend(sts_data[cgb_bit]);
            endaction
        endseq
    endseq;
endfunction

//poll STATUS.done until set (or rg_finished already True), then assert rg_finished
function Stmt bjpeg_poll_done(
    BlueCSRTbAccessor_ifc#(32) cfg_acc,
    Reg#(Bit#(32)) rg_rsp,
    Reg#(Bool) rg_finished);
    return seq
        rg_rsp <= 0;
        while(!unpack(rg_rsp[0])) seq
            cfg_acc.read_reg_req("STS");
            action
                let      sts_rsp  <- cfg_acc.read_reg_rsp();
                let      done_bit <- cfg_acc.field_bit("STS", "DONE");
                Bit#(32) sts_data = tpl_1(sts_rsp);
                rg_rsp <= zeroExtend(sts_data[done_bit]);
            endaction
        endseq
        print_mod_pre_color_t_s("DUT signaled done via STATUS register", GREEN);
        rg_finished <= True;
    endseq;
endfunction

endpackage
