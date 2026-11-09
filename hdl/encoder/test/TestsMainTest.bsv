package TestsMainTest;

import StmtFSM :: *;
import BlueAXI :: *;

import TestHelper :: *;
import PrintUtil :: *;
import BlueJPEG :: *;
import SimRAM_AXI :: *;

(* synthesize *)
module [Module] mkTestsMainTest(TestHelper::TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;

    BlueJPEG dut <- mkBlueJPEG();

    Stmt s = {
        seq
            print_s("Hello World from the testbench.", YELLOW);
        endseq
    };
    FSM i_test_fsm <- mkFSM(s);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod
endmodule

endpackage
