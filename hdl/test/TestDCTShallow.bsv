package TestDCTShallow;

import FIFO :: *;
import LFSR :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import ClientServer :: *;

import BDPI :: *;
import EncoderUtil :: *;
import DCT2D_Optimized :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;

/*
 * Feeds the same rows to the deep and the shallow rigid 2D DCT and requires bit-identical
 * outputs. Inputs include full-scale blocks, and both outputs stall at random, independently,
 * so the stall and bubble handling of both pipelines is exercised.
 */
(* synthesize *)
module [Module] mkTestDCTShallow(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;

    NumProxy_t#(12)       dct_scale = ?;
    DCT2DOptRigid_ifc#(8) i_deep    <- mkDCT2D_Opt_rigid(dct_scale, False, True, False, False, False);
    DCT2DOptRigid_ifc#(8) i_shallow <- mkDCT2D_Opt_rigid(dct_scale, False, True, False, False, True);

    Integer n_rows = 8 * 2000;

    FIFO#(Vector#(8, Int#(15))) f_deep    <- mkSizedFIFO(64);
    FIFO#(Vector#(8, Int#(15))) f_shallow <- mkSizedFIFO(64);
    LFSR#(Bit#(16))             i_stall_a <- mkLFSR_16;
    LFSR#(Bit#(16))             i_stall_b <- mkLFSR_16;

    Reg#(UInt#(32)) rg_sent     <- mkReg(0);
    Reg#(UInt#(32)) rg_compared <- mkReg(0);
    Reg#(UInt#(32)) rg_errors   <- mkReg(0);
    Reg#(Bool)      rg_init     <- mkReg(False);

    rule r_init (!rg_init);
        i_stall_a.seed('h1234);
        i_stall_b.seed('hbeef);
        rg_init <= True;
    endrule

    //both DCTs take the same row in the same cycle
    rule r_send (rg_init && rg_sent < fromInteger(n_rows));
        Vector#(8, Int#(8)) row = newVector;
        Bool extreme = (rg_sent / 8) % 5 == 0;
        for(Integer i = 0; i < 8; i = i + 1) begin
            let p <- rand_pix();
            Int#(16) v = unpack(zeroExtend(pack(p))) - 128;
            if(extreme) v = (pack(p)[0] == 1) ? 127 : -128;
            row[i] = truncate(v);
        end
        i_deep.data.request.put(row);
        i_shallow.data.request.put(row);
        rg_sent <= rg_sent + 1;
    endrule

    rule r_deep_out (rg_init && i_stall_a.value[1:0] != 0);
        let v <- i_deep.data.response.get;
        f_deep.enq(v);
    endrule

    rule r_shallow_out (rg_init && i_stall_b.value[2:0] != 0);
        let v <- i_shallow.data.response.get;
        f_shallow.enq(v);
    endrule

    (* fire_when_enabled *)
    rule r_lfsr (rg_init);
        i_stall_a.next;
        i_stall_b.next;
    endrule

    rule r_compare;
        let a = f_deep.first;
        f_deep.deq;
        let b = f_shallow.first;
        f_shallow.deq;
        if(a != b) begin
            rg_errors <= rg_errors + 1;
            if(rg_errors < 4) $display("ERROR: row %0d deep ", rg_compared, fshow(a), " shallow ", fshow(b));
        end
        rg_compared <= rg_compared + 1;
    endrule

    Stmt s = seq
        await(rg_compared == fromInteger(n_rows));
        if(rg_errors == 0)
            print_s("TestDCTShallow PASSED, deep and shallow DCT bit-identical", GREEN);
        else
            $display("ERROR: %0d of %0d rows differ", rg_errors, n_rows);
    endseq;

    FSM i_fsm <- mkFSM(s);

    method Action go();
        i_fsm.start();
    endmethod

    method Bool done();
        return i_fsm.done();
    endmethod

endmodule

endpackage
