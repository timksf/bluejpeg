package TestJPEGBitstream;

import Vector :: *;
import GetPut :: *;
import ClientServer :: *;
import StmtFSM :: *;

import Types :: *;
import JPEGBitstream :: *;
import TestHelper :: *;

typedef struct {
    Vector#(4, HuffCode_t) words;
    UInt#(3)               word_count;
    Bit#(256)              bytes;
    UInt#(6)               byte_count;
} BitstreamCase_t deriving(Bits, Eq, FShow);

function HuffCode_t codeword(Bit#(32) bits, Bit#(5) size, Bool last);
    return HuffCode_t { huffcode: bits, huffsize: size, last: last };
endfunction

function BitstreamCase_t test_case(UInt#(4) idx);
    BitstreamCase_t result = BitstreamCase_t {
        words: replicate(codeword(0, 0, True)),
        word_count: 1, bytes: 0, byte_count: 0
    };
    case(idx)
        0: begin //empty scan: no padding byte
            result.words[0] = codeword(0, 0, True);
        end
        1: begin //byte aligned, with no extra padding byte
            result.words[0] = codeword('h1234, 16, False);
            result.words[1] = codeword('h5678, 16, True);
            result.word_count = 2;
            result.bytes = 'h12345678;
            result.byte_count = 4;
        end
        2: begin //stuff an aligned final FF before declaring completion
            result.words[0] = codeword('h12ffff, 24, True);
            result.bytes = 'h12ff00ff00;
            result.byte_count = 5;
        end
        3: begin //cross-codeword byte assembly, bits above huffsize are ignored
            //101 ++ 01011 = AB and 110 ++ padding 11111 = DF
            result.words[0] = codeword(32'hfffffff8 | 'b101, 3, False);
            result.words[1] = codeword('b01011, 5, False);
            result.words[2] = codeword('b110, 3, True);
            result.word_count = 3;
            result.bytes = 'habdf;
            result.byte_count = 2;
        end
        4: begin //seven padding bits produce FF, which also needs stuffing
            result.words[0] = codeword(1, 1, True);
            result.bytes = 'hff00;
            result.byte_count = 2;
        end
        5: begin //maximum-size words offered back-to-back, repeated stuffing
            //4 * 31 ones + 4 padding ones = 16 FF bytes before stuffing
            result.words = replicate(codeword(32'hffffffff >> 1, 31, False));
            result.words[3] = codeword(32'hffffffff >> 1, 31, True);
            result.word_count = 4;
            result.bytes = 'hff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00_ff00;
            result.byte_count = 32;
        end
        6: begin //long words crossing byte boundaries, then padding/stuffing
            //write the desired pre-stuffing bytes in stream order, then
            //extract three consecutive 31-bit words, right-aligned for put
            //bits [2:0] are omitted: the DUT supplies these three padding ones
            Bit#(96) scan_bits = 96'h12_34_56_78_9a_bc_de_f0_ff_ff_ff_ff;
            result.words[0] = codeword(zeroExtend(scan_bits[95:65]), 31, False);
            result.words[1] = codeword(zeroExtend(scan_bits[64:34]), 31, False);
            result.words[2] = codeword(zeroExtend(scan_bits[33:3]), 31, True);
            result.word_count = 3;
            result.bytes = 'h12_34_56_78_9a_bc_de_f0_ff00_ff00_ff00_ff00;
            result.byte_count = 16;
        end
        7: begin //a separate zero-length last word flushes pending bits
            //10 ++ padding 111111 = BF
            result.words[0] = codeword('b10, 2, False);
            result.words[1] = codeword('hffffffff, 0, True);
            result.word_count = 2;
            result.bytes = 'hbf;
            result.byte_count = 1;
        end
        8: begin //one padding bit, and a zero-length non-last word adds nothing
            result.words[0] = codeword('hffffffff, 0, False);
            //A8's first seven bits ++ padding 1 = A9
            result.words[1] = codeword(32'ha8 >> 1, 7, True);
            result.word_count = 2;
            result.bytes = 'ha9;
            result.byte_count = 1;
        end
    endcase
    return result;
endfunction

module mkTestJPEGBitstreamMode#(Bool buffer_in, Bool backpressure)(TestHandler_ifc);

    JPEGBitstream_ifc i_dut <- mkJPEGBitstream(buffer_in);

    Reg#(UInt#(4))  rg_case     <- mkReg(0);
    Reg#(UInt#(3))  rg_sent     <- mkReg(0);
    Reg#(UInt#(6))  rg_received <- mkReg(0);
    Reg#(UInt#(16)) rg_cycles   <- mkReg(0);
    Reg#(Bool)      rg_active   <- mkReg(False);

    //stalls are stimulus only: neither the sender nor the checker assumes a response latency
    //the watchdog turns a missing byte/done into a failure
    rule r_tick (rg_active);
        rg_cycles <= rg_cycles + 1;
    endrule

    rule r_watchdog (rg_active && rg_cycles == 10000);
        $display("FAIL JPEGBitstream buffer_in=%0d backpressure=%0d case=%0d: timeout, sent=%0d received=%0d done=%0d",
                 buffer_in, backpressure, rg_case, rg_sent, rg_received, i_dut.scan_done);
        $finish(1);
    endrule

    rule r_send (rg_active && rg_sent < test_case(rg_case).word_count);
        i_dut.data.request.put(test_case(rg_case).words[rg_sent]);
        rg_sent <= rg_sent + 1;
    endrule

    //hold off initially to fill queues, then accept only one cycle in eight
    rule r_check (rg_active && (!backpressure || (rg_cycles >= 40 && rg_cycles % 8 == 0)));
        let      actual     <- i_dut.data.response.get();
        let      example    = test_case(rg_case);
        UInt#(9) shift_bits = zeroExtend(example.byte_count - 1 - rg_received) * 8;
        Bit#(8)  expected   = truncate(example.bytes >> shift_bits);
        if(rg_received >= example.byte_count || actual != expected) begin
            $display("FAIL JPEGBitstream buffer_in=%0d backpressure=%0d case=%0d byte=%0d: got=%02h expected=%02h (expected count=%0d)",
                     buffer_in, backpressure, rg_case, rg_received, actual, expected, example.byte_count);
            $finish(1);
        end
        rg_received <= rg_received + 1;
    endrule

    Stmt test_seq = seq
        rg_case <= 0;
        while(rg_case < 9) seq
            i_dut.rewind();
            action
                if(i_dut.scan_done) begin
                    $display("FAIL JPEGBitstream: rewind did not clear scan_done");
                    $finish(1);
                end
                rg_sent <= 0;
                rg_received <= 0;
                rg_cycles <= 0;
                rg_active <= True;
            endaction
            await(rg_sent == test_case(rg_case).word_count && rg_received == test_case(rg_case).byte_count && i_dut.scan_done);
            //keep consuming after completion to catch unexpected trailing bytes
            //this is a quiet observation window, not a DUT latency assertion
            delay(64);
            rg_active <= False;
            rg_case <= rg_case + 1;
        endseq
        $display("PASS JPEGBitstream buffer_in=%0d backpressure=%0d (9 cases)", buffer_in, backpressure);
    endseq;

    FSM i_test <- mkFSM(test_seq);

    method Action go() = i_test.start();
    method Bool done() = i_test.done();

endmodule

module [Module] mkTestJPEGBitstream(TestHandler_ifc);

    TestHandler_ifc i_bypass           <- mkTestJPEGBitstreamMode(False, False);
    TestHandler_ifc i_bypass_stalled   <- mkTestJPEGBitstreamMode(False, True);
    TestHandler_ifc i_buffered         <- mkTestJPEGBitstreamMode(True, False);
    TestHandler_ifc i_buffered_stalled <- mkTestJPEGBitstreamMode(True, True);

    Stmt test_seq = seq
        i_bypass.go();
        await(i_bypass.done());
        i_bypass_stalled.go();
        await(i_bypass_stalled.done());
        i_buffered.go();
        await(i_buffered.done());
        i_buffered_stalled.go();
        await(i_buffered_stalled.done());
        $display("TestJPEGBitstream PASSED");
    endseq;

    FSM i_test <- mkFSM(test_seq);

    method Action go() = i_test.start();
    method Bool done() = i_test.done();

endmodule

endpackage
