package JPEGBitstream;

import FIFO :: *;
import FIFOF :: *;
import GetPut :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import Types :: *;

interface JPEGBitstream_ifc;
    method Bool scan_done();
    method Action rewind();
    interface Server#(HuffCode_t, Bit#(8)) data;
endinterface

module mkJPEGBitstream#(Bool buffer_in)(JPEGBitstream_ifc);

    FIFO#(HuffCode_t) f_in;
    FIFO#(Bit#(8))  f_out   <- mkFIFO;
    FIFOF#(Bit#(8)) f_bytes <- mkFIFOF;

    if(buffer_in)
        f_in <- mkFIFO;
    else
        f_in <- mkBypassFIFO;

    //only the low rg_bits bits are valid, emission changes the count without clearing data
    //the count CReg allows emission and accumulation in the same cycle
    Reg#(Bit#(64)) rg_buffer  <- mkReg(0);
    Reg#(UInt#(7)) rg_bits[2] <- mkCReg(2, 0);

    //stuffing: after emitting 0xFF, must emit 0x00
    Reg#(Bool) rg_stuff <- mkReg(False);

    //flush state machine
    Reg#(Bool) rg_finishing    <- mkReg(False); //seen last flag, draining bytes
    Reg#(Bool) rg_pad_injected <- mkReg(False); //padding bits have been added
    Reg#(Bool) rg_done         <- mkReg(False); //scan complete

    //rewind only pulses, r_rewind owns the reset and the other rules stand still in that cycle
    PulseWire pw_rewind <- mkPulseWire;

    //emission and flush rules can update the low count port without priority
    (* conflict_free = "r_emit, r_stuff, r_pad, r_pad_done, r_check_done" *)

    //accept new codeword when buffer has room (port 1 sees emit updates)
    rule r_accumulate (!pw_rewind && !rg_finishing && rg_bits[1] <= 32);
        let cw = f_in.first; f_in.deq;

        Bit#(5)  sz       = cw.huffsize;
        Bit#(32) mask     = ~(32'hffffffff << sz);
        Bit#(64) new_bits = zeroExtend(cw.huffcode & mask);

        rg_buffer  <= (rg_buffer << sz) | new_bits;
        rg_bits[1] <= rg_bits[1] + zeroExtend(unpack(sz));

        if(cw.last) rg_finishing <= True;
    endrule

    //emit full bytes from the accumulator msb-first (port 0)
    rule r_emit (!pw_rewind && rg_bits[0] >= 8);
        Bit#(7) shift_amt = pack(rg_bits[0] - 8);
        Bit#(8) out_byte  = truncate(rg_buffer >> shift_amt);
        f_bytes.enq(out_byte);
        rg_bits[0] <= rg_bits[0] - 8;
    endrule

    //a registered byte boundary separates extraction from stuffing detection
    rule r_forward (!pw_rewind && !rg_stuff);
        let out_byte = f_bytes.first;
        f_bytes.deq;
        f_out.enq(out_byte);
        rg_stuff <= out_byte == 8'hff;
    endrule

    //emit 0x00 stuffing byte after 0xFF
    rule r_stuff (!pw_rewind && rg_stuff);
        f_out.enq(8'h00);
        rg_stuff <= False;
    endrule

    //flush: inject 1-bit padding to complete the final byte
    rule r_pad (!pw_rewind && rg_finishing && !rg_pad_injected && rg_bits[0] > 0 && rg_bits[0] < 8 && !rg_stuff);
        Bit#(3) pad  = truncate(pack(8 - rg_bits[0]));
        Bit#(8) ones = ~(8'hff << pad);
        Bit#(8) tail = truncate(rg_buffer);
        rg_buffer <= zeroExtend((tail << pad) | ones);
        rg_bits[0] <= 8;
        rg_pad_injected <= True;
    endrule

    //flush with zero remaining bits (codeword aligned to byte boundary)
    rule r_pad_done (!pw_rewind && rg_finishing && !rg_pad_injected && rg_bits[0] == 0 && !rg_stuff && !f_bytes.notEmpty);
        rg_done <= True;
        rg_finishing <= False;
    endrule

    //final byte emitted and all stuffing done -> signal completion
    rule r_check_done (!pw_rewind && rg_finishing && rg_pad_injected && rg_bits[0] == 0 && !rg_stuff && !f_bytes.notEmpty);
        rg_done <= True;
        rg_finishing <= False;
        rg_pad_injected <= False;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_rewind (pw_rewind);
        rg_buffer       <= 0;
        rg_bits[0]       <= 0;
        rg_stuff        <= False;
        rg_finishing    <= False;
        rg_pad_injected <= False;
        rg_done         <= False;
        f_in.clear;
        f_out.clear;
        f_bytes.clear;
    endrule

    method Bool scan_done() = rg_done;
    method rewind = pw_rewind.send;

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage
