package TbJpegUdpDemo;

import Clocks :: *;

import JpegUdpSystem :: *;
import TestHelper :: *;
import TestJpegUdpSystem :: *;

module [Module] mkTbJpegUdpDemo(TestHandler_ifc);
    let encoder_clock <- exposeCurrentClock;
    let encoder_reset <- exposeCurrentReset;
    //periods 10, 16, 80 and 25 model 200, 125, 25 and conservative 80 MHz domains
    let system_clock <- mkAbsoluteClock(3, 16);
    let system_reset <- mkAsyncReset(2, encoder_reset, system_clock);
    let i_divider <- mkClockDivider(8);
    let dct_reset <- mkAsyncReset(2, encoder_reset, i_divider.slowClock);
    let memory_clock <- mkAbsoluteClock(7, 25);
    let memory_reset <- mkAsyncReset(2, encoder_reset, memory_clock);
    let i_dut <- mkJpegUdpSystemAsync(True, encoder_clock, encoder_reset, i_divider.slowClock, dct_reset,
        clocked_by system_clock, reset_by system_reset);
    let i_test <- mkJpegUdpSystemTest(True, i_dut, memory_clock, memory_reset,
        clocked_by system_clock, reset_by system_reset);

    SyncFIFOIfc#(Bool) f_go <- mkSyncFIFOFromCC(2, system_clock);
    SyncBitIfc#(Bit#(1)) i_done <- mkSyncBit(system_clock, system_reset, encoder_clock);
    Reg#(Bool) rg_started <- mkReg(False, clocked_by system_clock, reset_by system_reset);
    rule r_go;
        f_go.deq;
        i_test.go;
        rg_started <= True;
    endrule
    rule r_done;
        i_done.send(pack(rg_started && i_test.done));
    endrule
    method Action go;
        f_go.enq(True);
    endmethod
    method done = i_done.read == 1;
endmodule

endpackage
