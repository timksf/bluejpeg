package Testbench;
    import Vector :: *;
    import StmtFSM :: *;

    import TestHelper :: *;

    //project modules
    import `RUN_TEST :: *;

    typedef 1 TestAmount;

    (* synthesize *)
    module [Module] mkTestbench();
        Vector#(TestAmount, TestHandler_ifc) testVec;
        testVec[0] <- `TESTNAME ();

        Reg#(UInt#(32)) rg_test_counter <- mkReg(0);
        Stmt s = {
            seq
                for(rg_test_counter <= 0;
                    rg_test_counter < fromInteger(valueOf(TestAmount));
                    rg_test_counter <= rg_test_counter + 1)
                seq
                    testVec[rg_test_counter].go();
                    await(testVec[rg_test_counter].done());
                endseq
            endseq
        };
        mkAutoFSM(s);
    endmodule

endpackage
