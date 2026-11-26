package IDCT;

import DReg :: *;
import FIFO :: *;
import FIFOF :: *;
import Real :: *;
import Vector :: *;
import GetPut :: *;
import Connectable :: *;
import ClientServer :: *;

import EncoderUtil :: *;
import SignedMul :: *;
import Types :: *;
import DCT1D :: *;
import TransposeBuffer :: *;

typedef Vector#(10, Int#(bits)) IDCTWork_t#(numeric type bits);

//integer bits each pass needs for clamped 12-bit coefficients (worst case over all sign patterns)
typedef 13 IDCTPass1Int;
typedef 15 IDCTPass2Int;

interface IDCT2D_ifc#(numeric type bits_in);
    method Action rewind();
    interface Server#(Vector#(8, Int#(bits_in)), Vector#(8, UInt#(8))) data;
endinterface

typedef struct {
    Integer c1414;
    Integer c1848;
    Integer c1082;
    Integer c2613;
} IDCTCoeffs_t;

//constants in signed Q2.cfrac, wide enough for 2.613
typedef TAdd#(cfrac, 3) IDCTCoeffBits#(numeric type cfrac);

function IDCTCoeffs_t prepare_idct_coeffs(Real scale);
    return IDCTCoeffs_t {
        c1414: round(1.414213562 * scale),
        c1848: round(1.847759065 * scale),
        c1082: round(1.082392200 * scale),
        c2613: round(2.613125930 * scale)
    };
endfunction

/*
 * Inverse AAN flowgraph (the transpose of the forward graph in DCT1D, same
 * form as the float IDCT in libjpeg). The input is expected to carry the AAN
 * prescale aan(u) * aan(v) / 8, which the decoder folds into dequantization.
 * Each stage works on a ten-slot vector so the stages can share one type.
 *
 *   a  w0..w7 = x0+x4, x0-x4, x2+x6, x2-x6, z13, z10, z11, z12
 *   b  w4 = tmp7, w6 = z11-z13, w8 = z10+z12
 *   m  rounded full-width products by 1.414, 1.414, 1.848, 1.082 and 2.613
 *   c  all slots back to the pass width, a plain shift
 *   d  w3 = tmp12 (even), w7 = tmp10, w5 = tmp12 (odd)
 *   e  w0, w1, w2, w9 = tmp0, tmp1, tmp2, tmp3 and w5 = tmp6
 *   f  w6 = tmp5
 *   g  w7 = tmp4
 *   h  output butterflies
 *
 * Inputs are bounded by the clamped coefficients, so plain wrapping adders
 * suffice as long as the pass widths cover IDCTPass1Int and IDCTPass2Int.
 */
function IDCTWork_t#(bits) idct_stage_a(IDCTWork_t#(bits) x);
    IDCTWork_t#(bits) w = replicate(0);
    w[0] = x[0] + x[4];
    w[1] = x[0] - x[4];
    w[2] = x[2] + x[6];
    w[3] = x[2] - x[6];
    w[4] = x[5] + x[3];
    w[5] = x[5] - x[3];
    w[6] = x[1] + x[7];
    w[7] = x[1] - x[7];
    return w;
endfunction

function IDCTWork_t#(bits) idct_stage_b(IDCTWork_t#(bits) w);
    IDCTWork_t#(bits) n = w;
    n[4] = w[6] + w[4];
    n[6] = w[6] - w[4];
    n[8] = w[5] + w[7];
    return n;
endfunction

//rounded full-width product, a Verilog signed multiply (see SignedMul.bs) with the rounding constant in the DSP post-adder
function Int#(m) mul_const_round(Integer frac, Int#(n) x, Int#(k) c)
    provisos(
        Add#(n, a__, m),
        Add#(k, b__, m)
    );
    return signed_mul_wide(x, c) + fromInteger(2 ** (frac - 1));
endfunction

//full-width products, slots without a multiplication are scaled so the shift in stage c passes them unchanged
function Vector#(10, Int#(bits_mul)) idct_stage_m(NumProxy_t#(cfrac) p, IDCTCoeffs_t c, IDCTWork_t#(bits) w)
    provisos(
        Add#(bits, IDCTCoeffBits#(cfrac), bits_mul)
    );
    function Int#(bits_mul) mul(Int#(bits) x, Integer k) = mul_const_round(valueOf(cfrac), x, Int#(IDCTCoeffBits#(cfrac))'(fromInteger(k)));
    function Int#(bits_mul) pass(Int#(bits) x) = signExtend(x) << valueOf(cfrac);

    Vector#(10, Int#(bits_mul)) n = map(pass, w);
    n[3] = mul(w[3], c.c1414);
    n[6] = mul(w[6], c.c1414);
    n[8] = mul(w[8], c.c1848);
    n[7] = mul(w[7], c.c1082);
    n[5] = mul(w[5], c.c2613);
    return n;
endfunction

//products are already rounded, so returning to the pass width is a shift
function IDCTWork_t#(bits) idct_stage_c(NumProxy_t#(cfrac) p, Vector#(10, Int#(bits_mul)) w)
    provisos(
        Add#(bits, a__, bits_mul)
    );
    function Int#(bits) narrow(Int#(bits_mul) x) = truncate(x >> valueOf(cfrac));
    return map(narrow, w);
endfunction

function IDCTWork_t#(bits) idct_stage_d(IDCTWork_t#(bits) w);
    IDCTWork_t#(bits) n = w;
    n[3] = w[3] - w[2];
    n[7] = w[8] - w[7];
    n[5] = w[8] - w[5];
    return n;
endfunction

function IDCTWork_t#(bits) idct_stage_e(IDCTWork_t#(bits) w);
    IDCTWork_t#(bits) n = w;
    n[0] = w[0] + w[2];
    n[9] = w[0] - w[2];
    n[1] = w[1] + w[3];
    n[2] = w[1] - w[3];
    n[5] = w[5] - w[4];
    return n;
endfunction

function IDCTWork_t#(bits) idct_stage_f(IDCTWork_t#(bits) w);
    IDCTWork_t#(bits) n = w;
    n[6] = w[6] - w[5];
    return n;
endfunction

function IDCTWork_t#(bits) idct_stage_g(IDCTWork_t#(bits) w);
    IDCTWork_t#(bits) n = w;
    n[7] = w[7] - w[6];
    return n;
endfunction

function Vector#(8, Int#(bits)) idct_stage_h(IDCTWork_t#(bits) w);
    Vector#(8, Int#(bits)) o = newVector;
    o[0] = w[0] + w[4];
    o[7] = w[0] - w[4];
    o[1] = w[1] + w[5];
    o[6] = w[1] - w[5];
    o[2] = w[2] + w[6];
    o[5] = w[2] - w[6];
    o[3] = w[9] + w[7];
    o[4] = w[9] - w[7];
    return o;
endfunction

/*
 * Rigid pipeline after mkDCT1D_rigid: one register per stage, valid bits
 * track bubbles and a single stall from the two-entry output FIFO freezes all
 * stages, so no ready signal ripples through the stage chain. Stages hold at
 * most two chained adders. The multiplication stage writes rounded
 * full-width products to their own register (the DSP output register) and
 * the next stage only shifts them back before its adders.
 *
 *   rg_n[0] -ab-> rg_n[1] -m-> rg_wide -cd-> rg_n[2] -e-> rg_n[3] -fg-> rg_n[4] -h-> f_out
 */
module mkIDCT1D#(NumProxy_t#(cfrac) p)(DCT1D_ifc#(bits))
    provisos(
        NumAlias#(TAdd#(bits, IDCTCoeffBits#(cfrac)), bits_mul)
    );

    let coeffs = prepare_idct_coeffs(2 ** fromInteger(valueOf(cfrac)));

    Vector#(5, Reg#(IDCTWork_t#(bits))) rg_n    <- replicateM(mkRegU);
    Reg#(Vector#(10, Int#(bits_mul)))   rg_wide <- mkRegU;

    //valid bits in pipeline order, index 2 belongs to rg_wide and index i + 1 to rg_n[i] for i >= 2
    Vector#(6, Reg#(Bool)) rg_valid = newVector;

    //the input valid is a DReg so idle cycles insert bubbles, it is held manually during stalls
    rg_valid[0] <- mkDReg(False);
    for(Integer i = 1; i < 6; i = i + 1)
        rg_valid[i] <- mkReg(False);

    FIFOF#(Vector#(8, Int#(bits))) f_out   <- mkFIFOF;
    Wire#(Bool)                    w_stall <- mkBypassWire;

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_stall;
        w_stall <= !f_out.notFull;
    endrule

    rule r_hold (w_stall);
        rg_valid[0] <= rg_valid[0];
    endrule

    rule r_advance (!w_stall);
        for(Integer i = 1; i < 6; i = i + 1)
            rg_valid[i] <= rg_valid[i - 1];
        rg_n[1] <= idct_stage_b(idct_stage_a(rg_n[0]));
        rg_wide <= idct_stage_m(p, coeffs, rg_n[1]);
        rg_n[2] <= idct_stage_d(idct_stage_c(p, rg_wide));
        rg_n[3] <= idct_stage_e(rg_n[2]);
        rg_n[4] <= idct_stage_g(idct_stage_f(rg_n[3]));
    endrule

    rule r_output (!w_stall && rg_valid[5]);
        f_out.enq(idct_stage_h(rg_n[4]));
    endrule

    method overflow = False;

    interface Server data;
        interface Put request;
            method Action put(Vector#(8, Int#(bits)) x) if(!w_stall);
                rg_n[0]     <= append(x, replicate(0));
                rg_valid[0] <= True;
            endmethod
        endinterface
        interface response = toGet(f_out);
    endinterface

endmodule

function UInt#(8) to_pixel(NumProxy_t#(dfrac) _p, Int#(bits) v)
    provisos(
        Add#(8, d__, bits)
    );
    Int#(bits) half = 1 << (valueOf(dfrac) - 1);
    Int#(bits) s    = ((v + half) >> valueOf(dfrac)) + 128;
    return s < 0 ? 0 : (s > 255 ? 255 : unpack(truncate(pack(s))));
endfunction

/*
 * Separable 2D IDCT. The block buffer delivers columns (fixed horizontal
 * frequency v), so the first pass transforms columns, the transpose buffer
 * turns them into rows and the second pass emits rows in natural order. The
 * second pass is two bits wider than the first, like the rigid forward DCT.
 * A last registered stage rounds away the dfrac fraction bits, adds the level
 * shift and clamps to 8-bit samples, so only pixel rows leave the module.
 */
module mkIDCT2D#(NumProxy_t#(cfrac) p, NumProxy_t#(dfrac) pd)(IDCT2D_ifc#(bits_in))
    provisos(
        NumAlias#(TAdd#(bits_in, TSub#(IDCTPass2Int, IDCTPass1Int)), bits_out),
        Add#(bits_in, a__, bits_out),
        Add#(bits_in, IDCTCoeffBits#(cfrac), mul_in),
        Add#(bits_out, IDCTCoeffBits#(cfrac), mul_out),
        Add#(bits_in, b__, mul_in),
        Add#(bits_out, c__, mul_out),
        Add#(8, d__, bits_out)
    );

    DCT1D_ifc#(bits_in)                    i_col <- mkIDCT1D(p);
    DCT1D_ifc#(bits_out)                   i_row <- mkIDCT1D(p);
    TransposeBufferOpt_ifc#(Int#(bits_in)) i_tp  <- mkTransposeBufferOpt;
    FIFO#(Vector#(8, UInt#(8)))            f_out <- mkFIFO;

    mkConnection(i_col.data.response, i_tp.original);

    rule r_row_input;
        let row <- i_tp.transposed.get;
        i_row.data.request.put(map(signExtend, row));
    endrule

    rule r_pixel;
        let row <- i_row.data.response.get;
        f_out.enq(map(to_pixel(pd), row));
    endrule

    method rewind = i_tp.rewind;

    interface Server data;
        interface request  = i_col.data.request;
        interface response = toGet(f_out);
    endinterface

endmodule

endpackage
