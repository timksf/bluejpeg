package DCT1D;

import BRAM :: *;
import FIFO :: *;
import Real :: *;
import DReg :: *;
import FIFOF :: *;
import Vector :: *;
import GetPut :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;
import DefaultValue :: *;

import EncoderUtil :: *;
import Types :: *;
import PrintUtil :: *;

interface DCT1D_ifc#(numeric type bits);
    method Bool overflow();
    interface Server#(Vector#(8, Int#(bits)), Vector#(8, Int#(bits))) data;
endinterface

typedef struct {
    Integer a1_i;
    Integer a2_i;
    Integer a3_i;
    Integer a4_i;
    Integer a5_i;
} AAN_Coeffs_t;

typedef struct {
    Integer s0_i;
    Integer s1_i;
    Integer s2_i;
    Integer s3_i;
    Integer s4_i;
    Integer s5_i;
    Integer s6_i;
    Integer s7_i;
} AAN_SCoeffs_t;

function AAN_Coeffs_t prepare_coeffs(Real scale);
    //constants typically get narrowed before multiplication during synthesis
    AAN_Coeffs_t coeffs;
    coeffs.a2_i = round(0.54119610 * scale); //0.541
    coeffs.a1_i = round(0.70710678 * scale); //cos(pi/4)
    coeffs.a3_i = round(0.70710678 * scale); //cos(pi/4)
    coeffs.a4_i = round(1.30656296 * scale); //1.307 (this breaks scaling with bits_frac as its >1)
    coeffs.a5_i = round(0.38268343 * scale); //0.383
    return coeffs;
endfunction

function AAN_SCoeffs_t prepare_scoeffs(Real scale);
    //coefficients for output scaling (can be absorbed into quantization)
    AAN_SCoeffs_t scoeffs;
    scoeffs.s0_i = round(0.35355339 * scale);
    scoeffs.s1_i = round(0.25489779 * scale);
    scoeffs.s2_i = round(0.27059805 * scale);
    scoeffs.s3_i = round(0.30067244 * scale);
    scoeffs.s4_i = round(0.35355339 * scale);
    scoeffs.s5_i = round(0.44998811 * scale);
    scoeffs.s6_i = round(0.65328148 * scale);
    scoeffs.s7_i = round(1.28145772 * scale);
    return scoeffs;
endfunction

//butterfly add with saturation
function Int#(bits) bf_add(Bool safe_arith, Int#(bits) a, Int#(bits) b);
    Int#(bits) res = ?;
    if(safe_arith) begin
        res = satPlus(Sat_Bound, a, b);
    end else begin
        res = a + b;
    end
    return res;
endfunction

function Vector#(8, Int#(bits)) aan_stage0(Bool safe_arith, Vector#(8, Int#(bits)) in);
    Vector#(8, Int#(bits)) b = newVector;
    b[0] = bf_add(safe_arith,  in[0], in[7]);
    b[1] = bf_add(safe_arith,  in[1], in[6]);
    b[2] = bf_add(safe_arith,  in[2], in[5]);
    b[3] = bf_add(safe_arith,  in[3], in[4]);
    b[4] = bf_add(safe_arith, -in[4], in[3]);
    b[5] = bf_add(safe_arith, -in[5], in[2]);
    b[6] = bf_add(safe_arith, -in[6], in[1]);
    b[7] = bf_add(safe_arith, -in[7], in[0]);
    return b;
endfunction

function Vector#(8, Int#(bits)) aan_stage1(Bool safe_arith, Vector#(8, Int#(bits)) b);
    Vector#(8, Int#(bits)) c = newVector;
    c[0] = bf_add(safe_arith,  b[0],  b[3]);
    c[1] = bf_add(safe_arith,  b[1],  b[2]);
    c[2] = bf_add(safe_arith, -b[2],  b[1]);
    c[3] = bf_add(safe_arith, -b[3],  b[0]);
    c[4] = bf_add(safe_arith, -b[4], -b[5]);
    c[5] = bf_add(safe_arith,  b[5],  b[6]);
    c[6] = bf_add(safe_arith,  b[6],  b[7]);
    c[7] = b[7];
    return c;
endfunction

function Vector#(8, Int#(bits)) aan_stage2(Bool safe_arith, Vector#(8, Int#(bits)) c);
    Vector#(8, Int#(bits)) d = newVector;
    d[0] = bf_add(safe_arith,  c[0], c[1]);
    d[1] = bf_add(safe_arith, -c[1], c[0]);
    d[2] = bf_add(safe_arith,  c[2], c[3]);
    d[3] = c[3];
    d[4] = c[4];
    d[5] = c[5];
    d[6] = c[6];
    d[7] = c[7];
    return d;
endfunction

function Int#(bits) aan_stage2_helper(Bool safe_arith, Vector#(8, Int#(bits)) c);
    return bf_add(safe_arith, c[4], c[6]);
endfunction

function Vector#(8, Int#(bits)) aan_stage3(
    Bool safe_arith,
    NumProxy_t#(bits_frac) scale_proxy,
    AAN_Coeffs_t coeffs,
    Vector#(8, Int#(bits)) d
)
    provisos(
        Add#(bits_frac, 2, coeff_bits),
        Add#(bits, coeff_bits, bits_mul)
    );
    function mul = scaled_mul_s(safe_arith, safe_arith, scale_proxy);

    Vector#(8, Int#(bits)) m = newVector;
    m[0] = d[0];
    m[1] = d[1];
    m[2] = mul(d[2], coeffs.a1_i);
    m[3] = d[3];
    m[4] = mul(d[4], coeffs.a2_i);
    m[5] = mul(d[5], coeffs.a3_i);
    m[6] = mul(d[6], coeffs.a4_i);
    m[7] = d[7];
    return m;
endfunction

function Int#(bits) aan_stage3_helper(
    Bool safe_arith,
    NumProxy_t#(bits_frac) scale_proxy,
    AAN_Coeffs_t coeffs,
    Int#(bits) helper2
)
    provisos(
        Add#(bits_frac, 2, coeff_bits),
        Add#(bits, coeff_bits, bits_mul)
    );
    return scaled_mul_s(safe_arith, safe_arith, scale_proxy, helper2, coeffs.a5_i);
endfunction

function Vector#(8, Int#(bits)) aan_stage4(
    Bool safe_arith,
    Vector#(8, Int#(bits)) m,
    Int#(bits) helper3
);
    Vector#(8, Int#(bits)) e = newVector;
    e[0] = m[0];
    e[1] = m[1];
    e[2] = m[2];
    e[3] = m[3];
    e[4] = bf_add(safe_arith, -m[4], -helper3);
    e[5] = m[5];
    e[6] = bf_add(safe_arith,  m[6], -helper3);
    e[7] = m[7];
    return e;
endfunction

function Vector#(8, Int#(bits)) aan_stage5(Bool safe_arith, Vector#(8, Int#(bits)) e);
    Vector#(8, Int#(bits)) f = newVector;
    f[0] = e[0];
    f[1] = e[1];
    f[2] = bf_add(safe_arith, e[2],  e[3]);
    f[3] = bf_add(safe_arith, e[3], -e[2]);
    f[4] = e[4];
    f[5] = bf_add(safe_arith, e[5],  e[7]);
    f[6] = e[6];
    f[7] = bf_add(safe_arith, e[7], -e[5]);
    return f;
endfunction

function Vector#(8, Int#(bits)) aan_stage6(
    Bool safe_arith,
    Bool scale_out,
    NumProxy_t#(bits_frac) scale_proxy,
    AAN_SCoeffs_t scoeffs,
    Vector#(8, Int#(bits)) f
)
    provisos(
        Add#(bits_frac, 2, coeff_bits),
        Add#(bits, coeff_bits, bits_mul)
    );
    function mul = scaled_mul_s(safe_arith, safe_arith, scale_proxy);

    Vector#(8, Int#(bits)) g = newVector;
    g[0] = f[0];
    g[1] = f[1];
    g[2] = f[2];
    g[3] = f[3];
    g[4] = bf_add(safe_arith,  f[4],  f[7]);
    g[5] = bf_add(safe_arith,  f[5],  f[6]);
    g[6] = bf_add(safe_arith, -f[6],  f[5]);
    g[7] = bf_add(safe_arith,  f[7], -f[4]);

    Vector#(8, Int#(bits)) out = newVector;

    if(scale_out) begin
        Vector#(8, Int#(bits)) t = newVector;
        t[0] = mul(g[0], scoeffs.s0_i);
        t[1] = mul(g[1], scoeffs.s4_i);
        t[2] = mul(g[2], scoeffs.s2_i);
        t[3] = mul(g[3], scoeffs.s6_i);
        t[4] = mul(g[4], scoeffs.s5_i);
        t[5] = mul(g[5], scoeffs.s1_i);
        t[6] = mul(g[6], scoeffs.s7_i);
        t[7] = mul(g[7], scoeffs.s3_i);
        out[0] = t[0];
        out[4] = t[1];
        out[2] = t[2];
        out[6] = t[3];
        out[5] = t[4];
        out[1] = t[5];
        out[7] = t[6];
        out[3] = t[7];
    end else begin
        out[0] = truncate(g[0]);
        out[4] = truncate(g[1]);
        out[2] = truncate(g[2]);
        out[6] = truncate(g[3]);
        out[5] = truncate(g[4]);
        out[1] = truncate(g[5]);
        out[7] = truncate(g[6]);
        out[3] = truncate(g[7]);
    end

    return out;
endfunction


module mkDCT1D#(NumProxy_t#(bits_frac) _scale_proxy, Bool scale_out, Bool safe_arith)(DCT1D_ifc#(bits))
    provisos(
        Add#(bits_frac, 2, coeff_bits), //required for multiplication coefficients > a4, s7
        Add#(bits, coeff_bits, bits_mul)
    );
    //AAN algorithm, without scaling the output there are 5 multiplications total

    //maybe revise this later? but implicit control flow logic is nice...
    Vector#(7, FIFO#(Vector#(8, Int#(bits)))) f_stages  <- replicateM(mkPipelineFIFO);
    FIFO#(Int#(bits))                         f_helper2 <- mkPipelineFIFO;
    FIFO#(Int#(bits))                         f_helper3 <- mkPipelineFIFO;

    FIFO#(Vector#(8, Int#(bits))) f_out;

    if(scale_out)
        f_out <- mkPipelineFIFO;
    else
        f_out <- mkBypassFIFO;

    Real scale = 2 ** fromInteger(valueof(bits_frac));
    let coeffs  = prepare_coeffs(scale);
    let scoeffs = prepare_scoeffs(scale);

    //stage0
    rule r_stage0;
        let in = f_stages[0].first; f_stages[0].deq;
        f_stages[1].enq(aan_stage0(safe_arith, in));
    endrule

    //stage1
    rule r_stage1;
        let b = f_stages[1].first; f_stages[1].deq;
        f_stages[2].enq(aan_stage1(safe_arith, b));
    endrule

    //stage2
    rule r_stage2;
        let c = f_stages[2].first; f_stages[2].deq;
        f_helper2.enq(aan_stage2_helper(safe_arith, c));
        f_stages[3].enq(aan_stage2(safe_arith, c));
    endrule

    //stage3 - multiplications
    rule r_stage3;
        //helper stage to separate multiplications from additions
        let d       = f_stages[3].first; f_stages[3].deq;
        let helper2 = f_helper2.first; f_helper2.deq;
        f_helper3.enq(aan_stage3_helper(safe_arith, _scale_proxy, coeffs, helper2));
        f_stages[4].enq(aan_stage3(safe_arith, _scale_proxy, coeffs, d));
    endrule

    //stage4
    rule r_stage4;
        let m       = f_stages[4].first; f_stages[4].deq;
        let helper3 = f_helper3.first; f_helper3.deq;
        f_stages[5].enq(aan_stage4(safe_arith, m, helper3));
    endrule

    //stage5
    rule r_stage5;
        let e = f_stages[5].first; f_stages[5].deq;
        f_stages[6].enq(aan_stage5(safe_arith, e));
    endrule

    //stage6
    rule r_stage6;
        let f = f_stages[6].first; f_stages[6].deq;
        f_out.enq(aan_stage6(safe_arith, scale_out, _scale_proxy, scoeffs, f));
    endrule

    method overflow = False;

    interface data = toGPServer(f_stages[0], f_out);

endmodule


module mkDCT1D_rigid#(NumProxy_t#(bits_frac) _scale_proxy, Bool scale_out, Bool safe_arith)(DCT1D_ifc#(bits))
    provisos(
        Add#(bits_frac, 2, coeff_bits), //required for multiplication coefficients > a4, s7
        Add#(bits, coeff_bits, bits_mul)
    );

    Vector#(7, Reg#(Vector#(8, Int#(bits)))) rg_stages <- replicateM(mkRegU);
    Vector#(7, Reg#(Maybe#(Bit#(0))))        rg_stage_valid;

    //make the first register a DReg to avoid passing bubbles as valid elements
    rg_stage_valid[0] <- mkDReg(tagged Invalid);
    for(Integer i = 1; i < 7; i = i + 1) begin
        rg_stage_valid[i] <- mkReg(tagged Invalid);
    end

    Reg#(Int#(bits)) rg_helper2 <- mkRegU;
    Reg#(Int#(bits)) rg_helper3 <- mkRegU;

    FIFOF#(Vector#(8, Int#(bits))) f_out <- mkFIFOF; //mkPipelineFIFOF;

    Real scale = 2 ** fromInteger(valueof(bits_frac));
    let coeffs  = prepare_coeffs(scale);
    let scoeffs = prepare_scoeffs(scale);

    Wire#(Bool) w_stall <- mkBypassWire;

    /* Rigid pipeline with explicit bubble tracking */

    Action insert_pipe = action
        Bit#(0) t = ?;
        rg_stage_valid[0] <= tagged Valid t;
    endaction;

    //first register is DReg for input convenience but during stalls, we have to hold its value manually because of the auto reset
    rule r_hold_stage0 (w_stall);
        rg_stage_valid[0] <= rg_stage_valid[0];
    endrule

    for(Integer i = 1; i < 7; i = i + 1) begin
        rule r_advance (!w_stall);
            rg_stage_valid[i] <= rg_stage_valid[i-1];
        endrule
    end

    rule r_stage0 (!w_stall);
        rg_stages[1] <= aan_stage0(safe_arith, rg_stages[0]);
    endrule

    rule r_stage1 (!w_stall);
        let b = rg_stages[1];
        rg_stages[2] <= aan_stage1(safe_arith, b);
    endrule

    rule r_stage2 (!w_stall);
        let c = rg_stages[2];
        rg_helper2   <= aan_stage2_helper(safe_arith, c);
        rg_stages[3] <= aan_stage2(safe_arith, c);
    endrule

    rule r_stage3 (!w_stall);
        let d = rg_stages[3];
        rg_helper3   <= aan_stage3_helper(safe_arith, _scale_proxy, coeffs, rg_helper2);
        rg_stages[4] <= aan_stage3(safe_arith, _scale_proxy, coeffs, d);
    endrule

    rule r_stage4 (!w_stall);
        let m = rg_stages[4];
        rg_stages[5] <= aan_stage4(safe_arith, m, rg_helper3);
    endrule

    rule r_stage5 (!w_stall);
        let e = rg_stages[5];
        rg_stages[6] <= aan_stage5(safe_arith, e);
    endrule

    rule r_stage6 (!w_stall &&& rg_stage_valid[6] matches tagged Valid ._t);
        let f = rg_stages[6];
        f_out.enq(aan_stage6(safe_arith, scale_out, _scale_proxy, scoeffs, f));
    endrule

    rule r_stall;
        w_stall <= !f_out.notFull;
    endrule

    method overflow = False;

    interface Server data;
        interface Put request   = guard_put(expand_put(toPut(asReg(rg_stages[0])), insert_pipe), !w_stall);
        interface Get response  = toGet(f_out);
    endinterface

endmodule

endpackage
