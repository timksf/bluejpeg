package TbQuantizePipeline;

import GetPut :: *;
import StmtFSM :: *;
import ClientServer :: *;

import Quantize :: *;
import TestHelper :: *;
import Types :: *;

function Int#(15) sample_value(UInt#(9) index);
    Bit#(3) selection = truncate(pack(index));
    return case(selection)
        0: -16384;
        1:  16383;
        2: -1;
        3:  0;
        4:  1;
        5: -8193;
        6:  8191;
        7: -17;
    endcase;
endfunction

function Int#(12) table_value(QuantTableIdx_t index);
    Int#(12) mult = case(index.idx[2:0])
        0: -2048;
        1:  2047;
        2: -1;
        3:  0;
        4:  1;
        5: -131;
        6:  512;
        7:  197;
    endcase;
    return index.pt == Luma ? mult : ~mult;
endfunction

module mkTbQuantizePipeline(TestHandler_ifc);
    NumProxy_t#(12) scale = ?;
    Quant_ifc#(15) i_dut <- mkQuantize_RT(scale, False);

    Reg#(UInt#(9))  rg_sent     <- mkReg(0);
    Reg#(UInt#(9))  rg_received <- mkReg(0);
    Reg#(UInt#(3))  rg_modes    <- mkReg(0);
    Reg#(UInt#(16)) rg_cycle    <- mkReg(0);
    Reg#(Bool)      rg_active   <- mkReg(False);

    rule r_table;
        let index <- i_dut.qtable.request.get;
        i_dut.qtable.response.put(signExtend(table_value(index)));
    endrule

    rule r_tick (rg_active);
        rg_cycle <= rg_cycle + 1;
    endrule

    rule r_watchdog (rg_active && rg_cycle == 10000);
        $display("ERROR: quantizer timeout, sent=%0d received=%0d", rg_sent, rg_received);
        $finish(1);
    endrule

    rule r_modes (rg_active && rg_modes < 4);
        i_dut.du_mode.put((rg_modes & 1) == 0 ? Luma : Chroma);
        rg_modes <= rg_modes + 1;
    endrule

    rule r_send (rg_active && rg_sent < 256 && (rg_cycle < 200 || rg_cycle % 4 != 0));
        i_dut.data.request.put(sample_value(rg_sent));
        rg_sent <= rg_sent + 1;
    endrule

    rule r_check (rg_active && (rg_cycle >= 400 || (rg_cycle >= 80 && rg_cycle % 8 == 0)));
        let actual <- i_dut.data.response.get;
        QuantTableIdx_t index = QuantTableIdx_t {
            pt:  (rg_received & 64) == 0 ? Luma : Chroma,
            idx: truncate(pack(rg_received))
        };
        Int#(32) val     = signExtend(sample_value(rg_received));
        Int#(32) mult    = signExtend(table_value(index));
        Int#(32) rounded = val * mult + 2048;
        Int#(15) expected = truncate(rounded >> 12);
        if(rg_received >= 256 || actual != expected) begin
            $display("ERROR: quantizer sample=%0d got=%0d expected=%0d", rg_received, actual, expected);
            $finish(1);
        end
        rg_received <= rg_received + 1;
    endrule

    Stmt test_seq = seq
        //repeat after rewind to check that bubbles and stalled stages do not leak into the next run
        repeat(2) seq
            i_dut.rewind;
            action
                rg_sent <= 0;
                rg_received <= 0;
                rg_modes <= 0;
                rg_cycle <= 0;
                rg_active <= True;
            endaction
            await(rg_received == 256);
            delay(32);
            rg_active <= False;
        endseq
        $display("TbQuantizePipeline PASSED (signed extrema, bubbles, stalls and rewind)");
    endseq;
    FSM i_test <- mkFSM(test_seq);

    method Action go() = i_test.start;
    method Bool done() = i_test.done;
endmodule

endpackage
