package RLE;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import Types :: *;

interface RLE_ifc#(numeric type bits);
    method Action rewind();
    interface Put#(Bit#(2)) du_comp;
    interface Server#(Int#(bits), RLETag_t#(bits)) data;
endinterface

module mkRLE(RLE_ifc#(bits))
    provisos(
        Bits#(Int#(bits), _sz)
    );

    /*
        This is the first non-uniform pipeline stage outputting a compressed representation
        of the input data (quantization is theoretically not compression, although limited
        accuracy practically causes compression).
        This module is a prerequisite for huffman encoding. Has to perform following tasks:
        - detect number of consecutive zero AC coefficients in MCU for ZRL symbols
        - calculate DC coefficient diff in comparison to previous block
        - emit early EOB if only zeros remaining
        - output ordinary AC coefficients

        => this module does not do huffman encoding yet (contrary to software implementation)
        It emits (in that prio order):
        - DC diff for dc coefficients
        - early EOB if only zero AC coefficients remaining
        - ZRL if 16 consecutive zero AC coefficients
        - ordinary AC values
    */

    FIFO#(Int#(bits))      f_in  <- mkBypassFIFO;
    FIFO#(RLETag_t#(bits)) f_out <- mkFIFO;
    FIFO#(Tuple2#(Bool, Int#(bits))) f_classified <- mkFIFO;

    Reg#(Bit#(6)) rg_idx      <- mkReg(0);
    Reg#(Bit#(6)) rg_zero_run <- mkReg(0);

    //per-DU component ID via FIFO (0=Y, 1=Cb, 2=Cr)
    FIFO#(Bit#(2)) f_comp <- mkSizedFIFO(4);

    //separate DC predictor per component (JPEG requires per-component)
    Vector#(3, Reg#(Int#(bits))) rg_prev_dc <- replicateM(mkReg(0));

    function Reg#(Int#(bits)) prev_dc_reg(Bit#(2) comp);
        return asReg(rg_prev_dc[comp]);
    endfunction

    //when a non-zero AC follows >= 16 zeros, we must stall the input
    //to emit one or more ZRL tags before emitting the AC tag
    Reg#(Maybe#(Int#(bits))) rg_stall_val <- mkReg(tagged Invalid);

    //rewind only pulses, r_rewind owns the reset and the processing rules stand still in that cycle
    PulseWire pw_rewind <- mkPulseWire;

    rule r_classify (!pw_rewind);
        let val = f_in.first;
        f_in.deq;
        f_classified.enq(tuple2(val == 0, val));
    endrule

    rule r_process_dc (!pw_rewind && rg_idx == 0 && !isValid(rg_stall_val));
        match {.is_zero, .val} = f_classified.first;
        f_classified.deq;

        let comp = f_comp.first;
        let prev = prev_dc_reg(comp);

        f_out.enq(tagged DCDiff (val - prev));
        prev_dc_reg(comp) <= val;

        rg_idx      <= 1;
        rg_zero_run <= 0;
    endrule

    rule r_process_ac (!pw_rewind && rg_idx > 0 && !isValid(rg_stall_val));
        match {.is_zero, .val} = f_classified.first;
        f_classified.deq;

        if(is_zero) begin
            if(rg_idx == 63) begin
                //if last value is zero, emit EOB
                f_out.enq(tagged EOB);
                rg_idx      <= 0;
                rg_zero_run <= 0;
                f_comp.deq;
            end else begin
                //otherwise, skip over zeros
                rg_idx      <= rg_idx + 1;
                rg_zero_run <= rg_zero_run + 1;
            end
        end else begin
            //this branch ends a zero run of length N in [0, 63]
            if(rg_zero_run >= 16) begin
                //at least 16 consecutive zeros where encountered, emit as many ZRLs as required, followed by AC run
                f_out.enq(tagged ZRL);
                rg_zero_run     <= rg_zero_run - 16;
                rg_stall_val    <= tagged Valid val; //stall to emit the remaining runs/AC
            end else begin
                //directly emit AC run if less than 16 consecutive zeros
                f_out.enq(tagged AC ACRun_t { run: truncate(rg_zero_run), val: val });
                rg_zero_run <= 0;

                if(rg_idx == 63) begin
                    rg_idx <= 0; f_comp.deq;
                end else begin
                    rg_idx <= rg_idx + 1;
                end
            end
        end
    endrule

    rule r_process_zrl (!pw_rewind && isValid(rg_stall_val));
        let val = fromMaybe(?, rg_stall_val);

        if(rg_zero_run >= 16) begin
            f_out.enq(tagged ZRL);
            rg_zero_run <= rg_zero_run - 16;
        end else begin
            f_out.enq(tagged AC ACRun_t { run: truncate(rg_zero_run), val: val });
            rg_zero_run <= 0;
            rg_stall_val <= tagged Invalid; //clear stall

            if(rg_idx == 63) begin
                rg_idx <= 0; f_comp.deq;
            end else begin
                rg_idx <= rg_idx + 1;
            end
        end
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_rewind (pw_rewind);
        rg_idx       <= 0;
        rg_zero_run  <= 0;
        writeVReg(rg_prev_dc, replicate(0));
        rg_stall_val <= tagged Invalid;
        f_comp.clear;
        f_in.clear;
        f_classified.clear;
        f_out.clear;
    endrule

    method rewind = pw_rewind.send;

    interface du_comp = toPut(f_comp);
    interface data    = toGPServer(f_in, f_out);

endmodule

endpackage
