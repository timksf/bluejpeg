package HuffEncoder;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;
import ConfigReg :: *;

import Types :: *;
import Util :: *;

typedef struct {
    PixType_t mode;
    Bool      is_last;
} HuffDUMeta_t deriving(Eq, Bits, FShow);

typedef struct {
    Bool       is_dc;
    Bool       has_extra;
    Bit#(5)    mag;
    Bit#(bits) extra;
    Bool       last;
} HuffPending_t#(numeric type bits) deriving(Eq, Bits, FShow);

interface HuffEncoder_ifc#(numeric type bits);
    interface Put#(HuffDUMeta_t) du_meta;
    method Action rewind();

    //combinational table read clients, connected to TableStorage
    interface Client#(HuffCodeDCIdx_t, HuffTableEntry_t) huff_dc;
    interface Client#(HuffCodeACIdx_t, HuffTableEntry_t) huff_ac;

    interface Server#(RLETag_t#(bits), HuffCode_t) data;
endinterface

module mkHuffEncoder(HuffEncoder_ifc#(bits))
    provisos(
        Add#(1, a__, bits), //bits >= 1
        Add#(b__, bits, 32), //bits <= 32 (for zeroExtend to Bit#(32))
        Add#(bits, c__, TExp#(TLog#(bits))),  // for flog2/clz_gen
        Add#(d__, 5, TAdd#(TLog#(bits), 1))   // for truncate in calc_magnitude
    );

    FIFO#(RLETag_t#(bits))      f_in        <- mkBypassFIFO;
    FIFO#(HuffCode_t)           f_out       <- mkFIFO;
    FIFO#(HuffPending_t#(bits)) f_pending   <- mkPipelineFIFO;

    FIFO#(HuffDUMeta_t) f_meta       <- mkSizedFIFO(4);
    Reg#(Bit#(6))       rg_coeff_idx <- mkReg(0);

    //Registered table addresses split symbol generation from LUTRAM lookup.
    Reg#(HuffCodeDCIdx_t)     rg_dc_req <- mkReg(HuffCodeDCIdx_t { pt: Luma, idx: 0 });
    Wire#(HuffTableEntry_t)   w_dc_resp <- mkWire;
    Reg#(HuffCodeACIdx_t)     rg_ac_req <- mkReg(HuffCodeACIdx_t { pt: Luma, idx: 0 });
    Wire#(HuffTableEntry_t)   w_ac_resp <- mkWire;

    //calculate magnitude (number of significant bits) of a signed value
    //this is equivalent to floor(log2(abs(val))) + 1 for val != 0
    //for val == 0, abs_bits is all zeros so no bit matches and mag = 0
    function Bit#(5) calc_magnitude(Int#(bits) val);
        Bit#(bits) abs_val = pack(abs(val));
        Bit#(5) mag = 0;
        for (Integer i = 0; i < valueOf(bits); i = i + 1)
            if (abs_val[i] == 1) mag = fromInteger(i + 1);
        return mag;
    endfunction

    //calculate extra bits for a signed value per JPEG F.1.2.1.1
    //positive values: lower mag bits of val
    //negative values: lower mag bits of bitwise complement of abs(val)
    function Bit#(bits) calc_extra_bits(Int#(bits) val);
        let abs_bits = pack(abs(val));
        return (val < 0) ? ~abs_bits : abs_bits;
    endfunction

    rule r_prepare;
        let tag = f_in.first; f_in.deq;
        let meta = f_meta.first;

        HuffPending_t#(bits) pending = HuffPending_t {
            is_dc: False,
            has_extra: False,
            mag: 0,
            extra: 0,
            last: False
        };
        Bit#(7) next_idx = 0;

        case (tag) matches
            tagged DCDiff .val: begin
                Bit#(5) mag = calc_magnitude(val);
                rg_dc_req <= HuffCodeDCIdx_t { pt: meta.mode, idx: truncate(mag) };
                pending.is_dc = True;
                pending.has_extra = True;
                pending.mag = mag;
                pending.extra = calc_extra_bits(val);
                next_idx = 1;
            end

            tagged AC .ac: begin
                Bit#(5) mag_ac = calc_magnitude(ac.val);
                Bit#(4) mag4 = truncate(mag_ac);
                rg_ac_req <= HuffCodeACIdx_t { pt: meta.mode, idx: {ac.run, mag4} };
                pending.has_extra = True;
                pending.mag = mag_ac;
                pending.extra = calc_extra_bits(ac.val);
                next_idx = zeroExtend(rg_coeff_idx) + zeroExtend(ac.run) + 1;
            end

            tagged ZRL: begin
                rg_ac_req <= HuffCodeACIdx_t { pt: meta.mode, idx: 8'hF0 };
                next_idx = zeroExtend(rg_coeff_idx) + 16;
            end

            tagged EOB: begin
                rg_ac_req <= HuffCodeACIdx_t { pt: meta.mode, idx: 8'h00 };
                next_idx = 0;
            end
        endcase

        //detect end-of-block: EOB always ends a block;
        //AC/ZRL end a block if the coefficient index wraps past 63
        Bool is_eob = (tag matches tagged EOB ? True : False);
        Bool is_end_of_block = is_eob || (next_idx >= 64);

        pending.last = meta.is_last && is_end_of_block;

        if (is_end_of_block) f_meta.deq;

        rg_coeff_idx <= truncate(next_idx); //truncation wraps >= 64 to 0
        f_pending.enq(pending);
    endrule

    rule r_emit;
        let pending = f_pending.first; f_pending.deq;

        HuffTableEntry_t entry = pending.is_dc ? w_dc_resp : w_ac_resp;
        HuffCode_t out = HuffCode_t {
            huffcode: zeroExtend(entry.code),
            huffsize: entry.size,
            last: pending.last
        };

        if (pending.has_extra) begin
            Bit#(32) code_mask = (1 << pending.mag) - 1;
            Bit#(32) extra = zeroExtend(pending.extra) & code_mask;
            out.huffcode = (zeroExtend(entry.code) << pending.mag) | extra;
            out.huffsize = entry.size + pending.mag;
        end

        f_out.enq(out);
    endrule

    method Action rewind();
        rg_coeff_idx <= 0;
        f_meta.clear;
        f_in.clear();
        f_pending.clear();
        f_out.clear();
    endmethod

    interface du_meta = toPut(f_meta);

    interface huff_dc = toGPClient(rg_dc_req, asReg(w_dc_resp));
    interface huff_ac = toGPClient(rg_ac_req, asReg(w_ac_resp));

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage
