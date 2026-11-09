package TestDUDispatcher;

import Connectable :: *;
import GetPut :: *;
import StmtFSM :: *;

import ChannelSplitter :: *;
import DUDispatcher :: *;
import TestHelper :: *;
import Types :: *;

module mkTestDUDispatcher(TestHandler_ifc);

    ChannelSplitter_ifc i_splitter   <- mkChannelSplitter;
    DUDispatcher_ifc    i_dispatcher <- mkDUDispatcher;
    mkConnection(i_splitter.y, i_dispatcher.y);
    mkConnection(i_splitter.cb, i_dispatcher.cb);
    mkConnection(i_splitter.cr, i_dispatcher.cr);

    Reg#(UInt#(8))  rg_input_count  <- mkReg(0);
    Reg#(UInt#(9))  rg_output_count <- mkReg(0);
    Reg#(UInt#(16)) rg_cycles       <- mkReg(0);

    rule r_tick;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 4095) begin
            $display("ERROR: DU dispatcher timed out");
            $fatal(1);
        end
    endrule

    Stmt test = seq
        par
            while(rg_input_count < 128) action
                i_splitter.pix.put(YCbCr_t {
                    y: rg_input_count,
                    cb: rg_input_count + 64,
                    cr: rg_input_count + 128
                });
                rg_input_count <= rg_input_count + 1;
            endaction

            while(rg_output_count < 384) seq
                //pause the consumer across DU boundaries to exercise backpressure
                await(rg_cycles % 8 < 3);
                action
                    let actual <- i_dispatcher.pix.get();
                    UInt#(9) mcu       = rg_output_count / 192;
                    UInt#(9) component = (rg_output_count % 192) / 64;
                    UInt#(8) expected  = truncate(mcu * 64 + component * 64 + rg_output_count % 64);
                    if(actual != expected) begin
                        $display("ERROR: dispatcher output %0d: got %0d, expected %0d",
                            rg_output_count, actual, expected);
                        $fatal(1);
                    end
                    rg_output_count <= rg_output_count + 1;
                endaction
            endseq
        endpar
        $display("DU dispatcher passed: two MCUs with output backpressure");
    endseq;

    FSM i_fsm_test <- mkFSM(test);
    method Action go();
        i_fsm_test.start();
    endmethod
    method Bool done();
        return i_fsm_test.done();
    endmethod

endmodule

endpackage
