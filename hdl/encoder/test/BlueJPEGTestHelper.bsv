package BlueJPEGTestHelper;

import StmtFSM :: *;
import BlueAXI :: *;
import BlueJPEG :: *;
import PrintUtil :: *;
import AXI4_Lite_Test :: *;

import BlueCSR :: *;

//write image dimensions to the IMG_SIZE config register ({height, width}).
function Action bjpeg_cfg_img_size(
    BlueCSRTbLookup_t#(32, 32) csrs,
    AXI4_Lite_Master_Wr#(32, 32) cfg_wr,
    Bit#(16) width, Bit#(16) height);
    action
        if (lookup_blue_csr_reg_offset(csrs, "IMSZ") matches tagged Valid .addr) begin
            axi4_lite_write(cfg_wr, fromInteger(addr), {height, width});
        end
        else begin
            $display("BlueJPEGTestHelper register lookup failed for IMSZ");
            $finish();
        end
    endaction
endfunction

function Action bjpeg_cfg_subsampling(
    BlueCSRTbLookup_t#(32, 32) csrs,
    AXI4_Lite_Master_Wr#(32, 32) cfg_wr,
    Bit#(32) subsampling_mode);
    action
        if (lookup_blue_csr_reg_offset(csrs, "SUBS") matches tagged Valid .addr) begin
            axi4_lite_write(cfg_wr, fromInteger(addr), subsampling_mode);
        end
        else begin
            $display("BlueJPEGTestHelper register lookup failed for SUBS");
            $finish();
        end
    endaction
endfunction

function Action bjpeg_start(
    BlueCSRTbLookup_t#(32, 32) csrs,
    AXI4_Lite_Master_Wr#(32, 32) cfg_wr);
    action
        if (lookup_blue_csr_reg_offset(csrs, "CTRL") matches tagged Valid .ctrl_addr) begin
            if (lookup_blue_csr_field_at_offset(csrs, ctrl_addr, "START") matches tagged Valid .start_field) begin
                axi4_lite_write(cfg_wr, fromInteger(ctrl_addr), 1 << start_field.bit_offset);
            end
            else begin
                $display("BlueJPEGTestHelper field lookup failed for CTRL.START");
                $finish();
            end
        end
        else begin
            $display("BlueJPEGTestHelper register lookup failed for CTRL");
            $finish();
        end
    endaction
endfunction

//poll STATUS.ready until set (default table initialisation complete).
function Stmt bjpeg_wait_tables_ready(
    BlueCSRTbLookup_t#(32, 32) csrs,
    AXI4_Lite_Master_Rd#(32, 32) cfg_rd,
    Reg#(Bit#(32)) rg_rsp);
    Stmt s = fail_blue_csr_lookup("register", "STS");
    if (lookup_blue_csr_reg_offset(csrs, "STS") matches tagged Valid .sts_addr) begin
        s = fail_blue_csr_lookup("field", "STS.RDY");
        if (lookup_blue_csr_field_at_offset(csrs, sts_addr, "RDY") matches tagged Valid .rdy_field) begin
            s = seq
                wait_bit_set(cfg_rd, sts_addr, rdy_field.bit_offset, rg_rsp);
                print_mod_pre_color_t_s("Tables ready", GREEN);
            endseq;
        end
    end
    return s;
endfunction

//trigger Huffman codegen for htt_val and wait until STATUS.codegen_busy clears.
function Stmt bjpeg_trigger_codegen(
    BlueCSRTbLookup_t#(32, 32) csrs,
    AXI4_Lite_Master_Wr#(32, 32) cfg_wr,
    AXI4_Lite_Master_Rd#(32, 32) cfg_rd,
    Reg#(Bit#(32)) rg_rsp,
    Bit#(32) htt_val);
    Stmt s = fail_blue_csr_lookup("register", "CGEN");
    if (lookup_blue_csr_reg_offset(csrs, "CGEN") matches tagged Valid .cgen_addr) begin
        s = fail_blue_csr_lookup("register", "STS");
        if (lookup_blue_csr_reg_offset(csrs, "STS") matches tagged Valid .sts_addr) begin
            s = fail_blue_csr_lookup("field", "STS.CGB");
            if (lookup_blue_csr_field_at_offset(csrs, sts_addr, "CGB") matches tagged Valid .cgb_field) begin
                s = seq
                    action
                        axi4_lite_write(cfg_wr, fromInteger(cgen_addr), htt_val | (1 << 31));
                    endaction
                    rg_rsp <= 'hFFFF;
                    wait_bit_not_set(cfg_rd, sts_addr, cgb_field.bit_offset, rg_rsp);
                endseq;
            end
        end
    end
    return s;
endfunction

//poll STATUS.done until set (or rg_finished already True), then assert rg_finished.
function Stmt bjpeg_poll_done(
    BlueCSRTbLookup_t#(32, 32) csrs,
    AXI4_Lite_Master_Rd#(32, 32) cfg_rd,
    Reg#(Bit#(32)) rg_rsp,
    Reg#(Bool) rg_finished);
    Stmt s = fail_blue_csr_lookup("register", "STS");
    if (lookup_blue_csr_reg_offset(csrs, "STS") matches tagged Valid .sts_addr) begin
        s = fail_blue_csr_lookup("field", "STS.DONE");
        if (lookup_blue_csr_field_at_offset(csrs, sts_addr, "DONE") matches tagged Valid .done_field) begin
            s = seq
                wait_bit_set(cfg_rd, sts_addr, done_field.bit_offset, rg_rsp);
                print_mod_pre_color_t_s("DUT signaled done via STATUS register", GREEN);
                rg_finished <= True;
            endseq;
        end
    end
    return s;
endfunction

function Stmt bjpeg_read_reg(
    BlueCSRTbLookup_t#(32, 32) csrs,
    AXI4_Lite_Master_Rd#(32, 32) cfg_rd,
    String reg_ident,
    Reg#(Bit#(32)) rg_rsp);
    Stmt s = fail_blue_csr_lookup("register", reg_ident);
    if (lookup_blue_csr_reg_offset(csrs, reg_ident) matches tagged Valid .reg_addr) begin
        s = axil_read(cfg_rd, fromInteger(reg_addr), rg_rsp);
    end
    return s;
endfunction

endpackage
