package JPEGBitstream;

import FIFO :: *;
import GetPut :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import Types :: *;

interface JPEGBitstream_ifc;
    method Bool scan_done();
    method Action start_scan();
    interface Server#(HuffCode_t, Bit#(8)) data;
endinterface

module mkJPEGBitstream#(Bool buffer_in)(JPEGBitstream_ifc);

    FIFO#(HuffCode_t) f_in;
    FIFO#(Bit#(8))    f_out <- mkFIFO;

    if(buffer_in)
        f_in <- mkFIFO;
    else
        f_in <- mkBypassFIFO;

    //64 bit accumulator; CReg allows r_emit (port 0) and r_accumulate (port 1)
    //to fire in the same cycle.  Valid bits are in positions [rg_bits-1:0].
    Reg#(Bit#(64))  rg_buffer[2] <- mkCReg(2, 0);
    Reg#(UInt#(7))  rg_bits[2]   <- mkCReg(2, 0);

    //stuffing: after emitting 0xFF, must emit 0x00
    Reg#(Bool) rg_stuff[2] <- mkCReg(2, False);

    //flush state machine
    Reg#(Bool) rg_finishing    <- mkReg(False); //seen last flag, draining bytes
    Reg#(Bool) rg_pad_injected <- mkReg(False); //padding bits have been added
    Reg#(Bool) rg_done         <- mkReg(False); //scan complete

    //all port-0 rules are mutually exclusive
    (* conflict_free = "r_emit, r_stuff, r_pad, r_pad_done, r_check_done" *)

    //accept new codeword when buffer has room (port 1 sees emit updates)
    rule r_accumulate (!rg_finishing && rg_bits[1] <= 32 && !rg_stuff[1]);
        let cw = f_in.first; f_in.deq;

        Bit#(7) sz = zeroExtend(cw.huffsize);
        Bit#(64) mask = (1 << sz) - 1;
        Bit#(64) new_bits = zeroExtend(cw.huffcode) & mask;

        rg_buffer[1] <= (rg_buffer[1] << sz) | new_bits;
        rg_bits[1]   <= rg_bits[1] + unpack(sz);

        if (cw.last) rg_finishing <= True;
    endrule

    //emit full bytes from the accumulator msb-first (port 0)
    rule r_emit (rg_bits[0] >= 8 && !rg_stuff[0]);
        Bit#(7) shift_amt = pack(rg_bits[0] - 8);
        Bit#(8) out_byte = truncate(rg_buffer[0] >> shift_amt);
        f_out.enq(out_byte);
        rg_bits[0] <= rg_bits[0] - 8;

        //clear emitted bits so port 1 (accumulate) sees a clean buffer
        Bit#(64) remain_mask = (1 << shift_amt) - 1;
        rg_buffer[0] <= rg_buffer[0] & remain_mask;

        if (out_byte == 8'hFF) rg_stuff[0] <= True;
    endrule

    //emit 0x00 stuffing byte after 0xFF
    rule r_stuff (rg_stuff[0]);
        f_out.enq(8'h00);
        rg_stuff[0] <= False;
    endrule

    //flush: inject 1-bit padding to complete the final byte
    rule r_pad (rg_finishing && !rg_pad_injected && rg_bits[0] > 0 && rg_bits[0] < 8 && !rg_stuff[0]);
        Bit#(7) pad = pack(8 - rg_bits[0]);
        Bit#(64) ones = (1 << pad) - 1;
        rg_buffer[0] <= (rg_buffer[0] << pad) | ones;
        rg_bits[0] <= 8;
        rg_pad_injected <= True;
    endrule

    //flush with zero remaining bits (codeword aligned to byte boundary)
    rule r_pad_done (rg_finishing && !rg_pad_injected && rg_bits[0] == 0 && !rg_stuff[0]);
        rg_done <= True;
        rg_finishing <= False;
    endrule

    //final byte emitted and all stuffing done -> signal completion
    rule r_check_done (rg_finishing && rg_pad_injected && rg_bits[0] == 0 && !rg_stuff[0]);
        rg_done <= True;
        rg_finishing <= False;
        rg_pad_injected <= False;
    endrule

    method Bool scan_done() = rg_done;

    method Action start_scan();
        rg_done <= False;
    endmethod

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage
