package JPEGBitstream;

import FIFO :: *;
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
    FIFO#(Bit#(8))    f_out <- mkPipelineFIFO;

    if(buffer_in)
        f_in <- mkPipelineFIFO;
    else
        f_in <- mkBypassFIFO;

    //64 bit accumulator as there are at most 32 valid bits in each huffcode
    //valid bits are in positions [rg_bits-1:0]
    Reg#(Bit#(64))  rg_buffer       <- mkReg(0);
    Reg#(UInt#(7))  rg_bits         <- mkReg(0);

    //stuffing: after emitting 0xFF, must emit 0x00
    Reg#(Bool) rg_stuff <- mkReg(False);

    //flush state machine
    Reg#(Bool) rg_finishing    <- mkReg(False); //seen last flag, draining bytes
    Reg#(Bool) rg_pad_injected <- mkReg(False); //padding bits have been added
    Reg#(Bool) rg_done         <- mkReg(False); //scan complete

    //accept new codeword only when buffer has room and no pending operations
    rule r_accumulate (!rg_finishing && rg_bits < 8 && !rg_stuff);
        let cw = f_in.first; f_in.deq;

        Bit#(7) sz = zeroExtend(cw.huffsize);
        Bit#(64) mask = (1 << sz) - 1;
        Bit#(64) new_bits = zeroExtend(cw.huffcode) & mask;

        rg_buffer <= (rg_buffer << sz) | new_bits;
        rg_bits   <= rg_bits + unpack(sz);

        if (cw.last) rg_finishing <= True;
    endrule

    //emit full bytes from the accumulator from msb first
    rule r_emit (rg_bits >= 8 && !rg_stuff);
        Bit#(7) shift_amt = pack(rg_bits - 8);
        Bit#(8) out_byte = truncate(rg_buffer >> shift_amt);
        f_out.enq(out_byte);
        rg_bits <= rg_bits - 8;

        if (out_byte == 8'hFF) rg_stuff <= True;
    endrule

    //emit 0x00 stuffing byte after 0xFF
    rule r_stuff (rg_stuff);
        f_out.enq(8'h00);
        rg_stuff <= False;
    endrule

    //flush: inject 1-bit padding to complete the final byte
    rule r_pad (rg_finishing && !rg_pad_injected && rg_bits > 0 && rg_bits < 8 && !rg_stuff);
        Bit#(7) pad = pack(8 - rg_bits);
        Bit#(64) ones = (1 << pad) - 1;
        rg_buffer <= (rg_buffer << pad) | ones;
        rg_bits <= 8;
        rg_pad_injected <= True;
    endrule

    //flush with zero remaining bits (codeword aligned to byte boundary)
    rule r_pad_done (rg_finishing && !rg_pad_injected && rg_bits == 0 && !rg_stuff);
        rg_done <= True;
        rg_finishing <= False;
    endrule

    //final byte emitted and all stuffing done -> signal completion
    rule r_check_done (rg_finishing && rg_pad_injected && rg_bits == 0 && !rg_stuff);
        rg_done <= True;
        rg_finishing <= False;
        rg_pad_injected <= False;
    endrule

    method Bool scan_done() = rg_done;

    method Action rewind();
        rg_buffer       <= 0;
        rg_bits         <= 0;
        rg_stuff        <= False;
        rg_finishing    <= False;
        rg_pad_injected <= False;
        rg_done         <= False;
        f_in.clear();
        f_out.clear();
    endmethod

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage