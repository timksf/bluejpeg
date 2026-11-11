package HuffEncoder;

import FIFO :: *;
import FIFOF :: *;
import Vector :: *;
import GetPut :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;
import ConfigReg :: *;

import Types :: *;
import EncoderUtil :: *;

typedef struct {
    PixType_t mode;
    Bool      is_last;
} HuffDUMeta_t deriving(Bits, Eq, FShow);

typedef struct {
    Bool       is_dc;
    Bool       has_extra;
    Bit#(5)    mag;
    Bit#(bits) extra;
    Bool       last;
} HuffPending_t#(numeric type bits) deriving(Bits, Eq, FShow);

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
        Add#(bits, c__, TExp#(TLog#(bits))),  //for flog2/clz_gen
        Add#(d__, 5, TAdd#(TLog#(bits), 1))   //for truncate in calc_magnitude
    );

    FIFO#(RLETag_t#(bits)) f_in  <- mkBypassFIFO;
    FIFOF#(HuffCode_t)    f_out <- mkGFIFOF(True, False);

    Reg#(HuffPending_t#(bits)) rg_symbol  <- mkRegU;
    Reg#(Bit#(bits))           rg_abs     <- mkRegU;
    Reg#(Bit#(4))              rg_run     <- mkRegU;
    Reg#(PixType_t)            rg_mode    <- mkRegU;
    Reg#(HuffPending_t#(bits)) rg_pending <- mkRegU;
    Reg#(HuffPending_t#(bits)) rg_emit    <- mkRegU;
    Reg#(HuffTableEntry_t)     rg_entry   <- mkRegU;
    Vector#(3, Reg#(Bool))     rg_valid   <- replicateM(mkReg(False));
    PulseWire                  pw_input   <- mkPulseWire;

    FIFO#(HuffDUMeta_t) f_meta       <- mkSizedFIFO(4);
    Reg#(Bit#(6))       rg_coeff_idx <- mkReg(0);

    //rewind only pulses, r_rewind owns the reset and the processing rules stand still in that cycle
    PulseWire pw_rewind <- mkPulseWire;
    Bool      advance    = f_out.notFull && !pw_rewind;

    //registered table addresses split symbol generation from LUTRAM lookup
    Reg#(HuffCodeDCIdx_t)   rg_dc_req <- mkReg(HuffCodeDCIdx_t { pt: Luma, idx: 0 });
    Wire#(HuffTableEntry_t) w_dc_resp <- mkDWire(?);
    Reg#(HuffCodeACIdx_t)   rg_ac_req <- mkReg(HuffCodeACIdx_t { pt: Luma, idx: 0 });
    Wire#(HuffTableEntry_t) w_ac_resp <- mkDWire(?);

    //calculate magnitude (number of significant bits) of a signed value
    //this is equivalent to floor(log2(abs(val))) + 1 for val != 0
    //for val == 0, abs_bits is all zeros so no bit matches and mag = 0
    function Bit#(5) calc_magnitude(Bit#(bits) abs_val);
        Bit#(5)    mag     = 0;
        for(Integer i = 0; i < valueOf(bits); i = i + 1)
            if(abs_val[i] == 1) mag = fromInteger(i + 1);
        return mag;
    endfunction

    //calculate extra bits for a signed value per JPEG F.1.2.1.1
    //positive values: lower mag bits of val
    //negative values: lower mag bits of bitwise complement of abs(val)
    function Bit#(bits) calc_extra_bits(Int#(bits) val);
        let abs_bits = pack(abs(val));
        return (val < 0) ? ~abs_bits : abs_bits;
    endfunction

    rule r_prepare (advance);
        let tag  = f_in.first; f_in.deq;
        let meta = f_meta.first;

        HuffPending_t#(bits) pending = HuffPending_t {
            is_dc:     False,
            has_extra: False,
            mag:       0,
            extra:     0,
            last:      False
        };
        Bit#(7)    next_idx = 0;
        Bit#(bits) magnitude = 0;
        Bit#(4)    run       = 0;

        case(tag) matches
            tagged DCDiff .val: begin
                magnitude = pack(abs(val));
                pending.is_dc = True;
                pending.has_extra = True;
                pending.extra = calc_extra_bits(val);
                next_idx = 1;
            end

            tagged AC .ac: begin
                magnitude = pack(abs(ac.val));
                run = ac.run;
                pending.has_extra = True;
                pending.extra = calc_extra_bits(ac.val);
                next_idx = zeroExtend(rg_coeff_idx) + zeroExtend(ac.run) + 1;
            end

            tagged ZRL: begin
                run = 'hf;
                next_idx = zeroExtend(rg_coeff_idx) + 16;
            end

            tagged EOB: begin
                next_idx = 0;
            end
        endcase

        //detect end-of-block: EOB always ends a block
        //AC/ZRL end a block if the coefficient index wraps past 63
        Bool is_eob          = (tag matches tagged EOB ? True : False);
        Bool is_end_of_block = is_eob || (next_idx >= 64);

        pending.last = meta.is_last && is_end_of_block;

        if(is_end_of_block) f_meta.deq;

        rg_coeff_idx <= truncate(next_idx); //truncation wraps >= 64 to 0
        rg_symbol <= pending;
        rg_abs    <= magnitude;
        rg_run    <= run;
        rg_mode   <= meta.mode;
        pw_input.send;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_valid (advance);
        rg_valid[0] <= pw_input;
        rg_valid[1] <= rg_valid[0];
        rg_valid[2] <= rg_valid[1];
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_symbol (advance);
        let pending = rg_symbol;
        Bit#(5) mag = pending.has_extra ? calc_magnitude(rg_abs) : 0;
        pending.mag = mag;
        rg_pending <= pending;
        rg_dc_req <= HuffCodeDCIdx_t {
            pt:  rg_mode,
            idx: truncate(mag)
        };
        rg_ac_req <= HuffCodeACIdx_t {
            pt:  rg_mode,
            idx: {rg_run, truncate(mag)}
        };
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_lookup (advance);
        rg_entry <= rg_pending.is_dc ? w_dc_resp : w_ac_resp;
        rg_emit  <= rg_pending;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_emit (advance && rg_valid[2]);
        let pending = rg_emit;
        let entry   = rg_entry;
        HuffCode_t out = HuffCode_t {
            huffcode: zeroExtend(entry.code),
            huffsize: entry.size,
            last: pending.last
        };

        if(pending.has_extra) begin
            Bit#(32) code_mask = ~(32'hffffffff << pending.mag);
            Bit#(32) extra     = zeroExtend(pending.extra) & code_mask;
            out.huffcode = (zeroExtend(entry.code) << pending.mag) | extra;
            out.huffsize = entry.size + pending.mag;
        end

        f_out.enq(out);
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_rewind (pw_rewind);
        rg_coeff_idx <= 0;
        f_meta.clear;
        f_in.clear;
        writeVReg(rg_valid, replicate(False));
        f_out.clear;
    endrule

    method rewind = pw_rewind.send;

    interface du_meta = toPut(f_meta);

    interface huff_dc = toGPClient(rg_dc_req, asReg(w_dc_resp));
    interface huff_ac = toGPClient(rg_ac_req, asReg(w_ac_resp));

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage
