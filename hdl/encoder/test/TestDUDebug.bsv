package TestDUDebug;

import FIFO :: *;
import StmtFSM :: *;
import GetPut :: *;

import Util :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;
import DUDebug :: *;

module [Module] mkTestDUDebug(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    DUDebug_ifc#(Int#(12), 8, 8) dut <- mkDUDebug("BLOCK");

    Reg#(Int#(12)) rg_cnt_i <- mkReg(0);
    Reg#(Int#(12)) rg_cnt_o <- mkReg(0);

    Stmt s = seq
        par
            while(rg_cnt_i < 128) action
                dut.pix_i.put(rg_cnt_i);
                rg_cnt_i <= rg_cnt_i + 1;
            endaction
            while(rg_cnt_o < 128) action
                let pix <- dut.pix_o.get();
                if(pix != rg_cnt_o)
                    print_s("PIXEL MISMATCH", RED);
                rg_cnt_o <= rg_cnt_o + 1;
            endaction
        endpar
    endseq;

    FSM i_test_fsm <- mkFSM(s);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

endpackage