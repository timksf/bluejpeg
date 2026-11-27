package Dequantize;

import DReg :: *;
import FIFO :: *;
import FIFOF :: *;
import Real :: *;
import Vector :: *;
import GetPut :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import EncoderUtil :: *;
import Types :: *;
import ZigZag :: *;
import DecoderTypes :: *;

interface Dequantize_ifc#(numeric type bits);
    interface Client#(QuantIdx_t, UInt#(8))           quant;
    interface Server#(CoefToken_t, DeqToken_t#(bits)) data;

    //the last coefficient of a scan has read its table entry, one cycle later
    method Bool scan_done;
endinterface

//extra fraction bits of the prescale constants, removed again by rounding
typedef 6 PrescaleGuard;

//unsigned prescale constants and their product with a clamped 11-bit coefficient magnitude
typedef TSub#(TAdd#(dfrac, PrescaleGuard), 2) PrescaleBits#(numeric type dfrac);
typedef TAdd#(11, PrescaleBits#(dfrac))       PrescaleProd#(numeric type dfrac);

//aan(u) * aan(v) / 8 * 2^frac in zigzag order, all below 2^(frac - 2)
function Vector#(64, Integer) dequant_prescale(Integer frac);
    function Real aan(Integer k) = k == 0 ? 1.0 : cos(fromInteger(k) * pi / 16.0) * sqrt(2.0);

    Vector#(64, Integer) zz  = zigzag_indices(False);
    Vector#(64, Integer) res = newVector;
    for(Integer k = 0; k < 64; k = k + 1)
        res[k] = round(aan(zz[k] / 8) * aan(zz[k] % 8) / 8.0 * (2 ** fromInteger(frac)));
    return res;
endfunction

/*
 * Dequantization with the AAN prescale folded in, the counterpart of
 * mkQuantize_RT. Like the encoder's quantizer it multiplies magnitudes and
 * restores the sign at the end, so no stage combines negation with a
 * multiplication. Rigid stages share one advance condition.
 *
 *   0  quantization table request, token registered
 *   1  coefficient magnitude and sign, table entry
 *   2  |q| * Q (11 x 8 bits)
 *   3  clamp to the 11-bit baseline magnitude, prescale constant from ROM
 *   4  clamped magnitude * prescale
 *   out  rounding by PrescaleGuard bits, sign restored
 *
 * The clamp bounds every IDCT node (see IDCTPass1Int), so the IDCT needs no
 * saturating arithmetic. Tokens without a value pass through unchanged.
 * scan_done tells the frame parser when the last coefficient of a scan has
 * taken its table entry, after which the tables may change.
 */
module mkDequantize#(NumProxy_t#(dfrac) _p)(Dequantize_ifc#(bits))
    provisos(
        NumAlias#(PrescaleBits#(dfrac), pre_w),
        NumAlias#(PrescaleProd#(dfrac), prod_w),
        Add#(a__, TSub#(prod_w, PrescaleGuard), bits),
        Add#(PrescaleGuard, b__, prod_w)
    );

    Integer guard = valueOf(PrescaleGuard);

    Vector#(64, UInt#(pre_w)) prescale = map(fromInteger, dequant_prescale(valueOf(dfrac) + guard));

    FIFO#(CoefToken_t)        f_in  <- mkBypassFIFO;
    FIFOF#(DeqToken_t#(bits)) f_out <- mkGFIFOF(True, False);

    Reg#(QuantIdx_t) rg_req <- mkReg(unpack(0));
    Wire#(UInt#(8))  w_resp <- mkDWire(?);

    //rg_tok[i] and rg_valid[i] belong to the operands registered by stage i
    Vector#(5, Reg#(CoefToken_t)) rg_tok   <- replicateM(mkRegU);
    Vector#(5, Reg#(Bool))        rg_valid <- replicateM(mkReg(False));

    Reg#(Bool)          rg_neg   <- mkRegU;
    Reg#(UInt#(11))     rg_mag   <- mkRegU;
    Reg#(UInt#(8))      rg_q     <- mkRegU;
    Reg#(UInt#(19))     rg_prod1 <- mkRegU;
    Reg#(UInt#(11))     rg_coef  <- mkRegU;
    Reg#(UInt#(pre_w))  rg_pre   <- mkRegU;
    Reg#(UInt#(prod_w)) rg_prod2 <- mkRegU;

    //the sign travels with the operands through the later stages
    Vector#(3, Reg#(Bool)) rg_sign <- replicateM(mkRegU);

    PulseWire  pw_input <- mkPulseWire;
    Reg#(Bool) rg_done  <- mkDReg(False);
    Bool      advance   = f_out.notFull;

    rule r_table_req (advance);
        let t = f_in.first; f_in.deq;
        rg_req <= QuantIdx_t {
            tq: t.pos.tq,
            k:  t.pos.k
        };
        rg_tok[0] <= t;
        pw_input.send;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_valid (advance);
        rg_valid[0] <= pw_input;
        for(Integer i = 1; i < 5; i = i + 1)
            rg_valid[i] <= rg_valid[i - 1];
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_token (advance);
        for(Integer i = 1; i < 5; i = i + 1)
            rg_tok[i] <= rg_tok[i - 1];
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_magnitude (advance);
        let v = rg_tok[0].val;
        rg_mag  <= unpack(truncate(pack(abs(v))));
        rg_neg  <= v < 0;
        rg_q    <= w_resp;
        rg_done <= rg_valid[0] && rg_tok[0].pos.last_block && rg_tok[0].pos.last;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_mul_quant (advance);
        rg_prod1   <= extend(rg_mag) * extend(rg_q);
        rg_sign[0] <= rg_neg;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_clamp (advance);
        rg_coef    <= rg_prod1 > 2047 ? 2047 : truncate(rg_prod1);
        rg_pre     <= prescale[rg_tok[2].pos.k];
        rg_sign[1] <= rg_sign[0];
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_mul_prescale (advance);
        rg_prod2   <= extend(rg_coef) * extend(rg_pre);
        rg_sign[2] <= rg_sign[1];
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_round (advance && rg_valid[4]);
        UInt#(prod_w)                         rounded = (rg_prod2 + fromInteger(2 ** (guard - 1))) >> guard;
        UInt#(TSub#(prod_w, PrescaleGuard))   narrow  = truncate(rounded);
        Int#(bits)                            mag     = unpack(zeroExtend(pack(narrow)));
        let t = rg_tok[4];
        f_out.enq(DeqToken_t {
            pos:     t.pos,
            val:     rg_sign[2] ? -mag : mag,
            has_val: t.has_val
        });
    endrule

    interface quant = toGPClient(rg_req, asReg(w_resp));
    interface data  = toGPServer(f_in, f_out);

    method scan_done = rg_done;

endmodule

endpackage
