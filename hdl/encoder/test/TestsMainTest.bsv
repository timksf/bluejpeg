package TestsMainTest;

import StmtFSM :: *;

import TestHelper :: *;
import PrintUtil :: *;
import BlueJPEG :: *;
import BlueAXI :: *;
import SimRAM_AXI :: *;

(* synthesize *)
module [Module] mkTestsMainTest(TestHelper::TestHandler);

    function print_s = print_mod_pre_color_t_s;

    BlueJPEG dut <- mkBlueJPEG();

    Stmt s = {
        seq
            print_s("Hello World from the testbench.", YELLOW);
        endseq
    };
    FSM testFSM <- mkFSM(s);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod
endmodule

endpackage
