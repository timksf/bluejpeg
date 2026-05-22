package DCT1D;

import BRAM :: *;
import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import Real :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;
import DefaultValue :: *;

import Util :: *;
import Types :: *;
import PrintUtil :: *;

interface DCT1D_ifc#(numeric type bits);
    method Bool overflow();
    interface Server#(Vector#(8, Int#(bits)), Vector#(8, Int#(bits))) data;
endinterface

module mkDCT1D#(NumProxy#(bits_frac) _scale_proxy, Bool scale_out, Bool safe_arith)(DCT1D_ifc#(bits))
    provisos(
        Add#(bits_frac, 2, coeff_bits), //required for multiplication coefficients > a4, s7
        Add#(bits, coeff_bits, bits_mul)
    );
    //AAN algorithm, without scaling the output there are 5 multiplications total

    //maybe revise this later? but implicit control flow logic is nice...
    Vector#(7, FIFO#(Vector#(8, Int#(bits)))) f_stages <- replicateM(mkPipelineFIFO);
    FIFO#(Int#(bits)) f_helper2 <- mkPipelineFIFO;
    FIFO#(Int#(bits)) f_helper3 <- mkPipelineFIFO;

    FIFO#(Vector#(8, Int#(bits))) f_out;

    Reg#(SaturationMode) rg_sat_mode <- mkReg(Sat_Bound);
    
    if(scale_out)
        f_out <- mkPipelineFIFO;
    else
        f_out <- mkBypassFIFO;

    Real scale = 2 ** fromInteger(valueof(bits_frac));

    //constants typically get narrowed before multiplication during synthesis

    //coefficients from AAN algorithm
    Integer a1_i = round(0.70710678 * scale); //cos(pi/4)
    Integer a2_i = round(0.54119610 * scale); //0.541
    Integer a3_i = round(0.70710678 * scale); //cos(pi/4)
    Integer a4_i = round(1.30656296 * scale); //1.307 (this breaks scaling with bits_frac as its >1)
    Integer a5_i = round(0.38268343 * scale); //0.383

    //output scaling (can be absorbed into quantization)
    Integer s0_i = round(0.35355339 * scale);
    Integer s1_i = round(0.25489779 * scale);
    Integer s2_i = round(0.27059805 * scale);
    Integer s3_i = round(0.30067244 * scale);
    Integer s4_i = round(0.35355339 * scale);
    Integer s5_i = round(0.44998811 * scale);
    Integer s6_i = round(0.65328148 * scale);
    Integer s7_i = round(1.28145772 * scale);

    function mul = scaled_mul_s(safe_arith, safe_arith, _scale_proxy);

    //butterfly add with saturation
    function Int#(bits) bf_add(Int#(bits) a, Int#(bits) b);
        Int#(bits) res = ?;
        if(safe_arith) begin
            res = satPlus(rg_sat_mode, a, b);
        end else begin
            res = a + b;
        end
        return res;
    endfunction

    //stage0
    rule rstage0;
        let in = f_stages[0].first; f_stages[0].deq;
        Vector#(8, Int#(bits)) b = newVector;
        b[0] = bf_add( in[0], in[7]);
        b[1] = bf_add( in[1], in[6]);
        b[2] = bf_add( in[2], in[5]);
        b[3] = bf_add( in[3], in[4]);
        b[4] = bf_add(-in[4], in[3]);
        b[5] = bf_add(-in[5], in[2]);
        b[6] = bf_add(-in[6], in[1]);
        b[7] = bf_add(-in[7], in[0]);
        f_stages[1].enq(b);
    endrule

    //stage1
    rule rstage1;
        let b = f_stages[1].first; f_stages[1].deq;
        Vector#(8, Int#(bits)) c = newVector;
        c[0] = bf_add( b[0],  b[3]);
        c[1] = bf_add( b[1],  b[2]);
        c[2] = bf_add(-b[2],  b[1]);
        c[3] = bf_add(-b[3],  b[0]);
        c[4] = bf_add(-b[4], -b[5]);
        c[5] = bf_add( b[5],  b[6]);
        c[6] = bf_add( b[6],  b[7]);
        c[7] = b[7];
        f_stages[2].enq(c);
    endrule

    //stage2
    rule rstage2;
        let c = f_stages[2].first; f_stages[2].deq;
        Vector#(8, Int#(bits)) d = newVector;
        d[0] = bf_add( c[0], c[1]);
        d[1] = bf_add(-c[1], c[0]);
        d[2] = bf_add( c[2], c[3]);
        d[3] = c[3];
        d[4] = c[4];
        d[5] = c[5];
        d[6] = c[6];
        d[7] = c[7];

        Int#(bits) helper2 = bf_add(c[4], c[6]);

        f_helper2.enq(helper2);
        f_stages[3].enq(d);
    endrule

    //stage3 - multiplications
    rule rstage3;
        //helper stage to separate multiplications from additions
        let d = f_stages[3].first; f_stages[3].deq;
        let helper2 = f_helper2.first; f_helper2.deq;
        Vector#(8, Int#(bits)) m = newVector;
        Int#(bits) helper3 = mul(helper2, a5_i);

        m[0] = d[0];
        m[1] = d[1];
        m[2] = mul(d[2], a1_i);
        m[3] = d[3];
        m[4] = mul(d[4], a2_i);
        m[5] = mul(d[5], a3_i);
        m[6] = mul(d[6], a4_i);
        m[7] = d[7];

        f_helper3.enq(helper3);
        f_stages[4].enq(m);
    endrule

    //stage4
    rule rstage4;
        let m = f_stages[4].first; f_stages[4].deq;
        let helper3 = f_helper3.first; f_helper3.deq;
        Vector#(8, Int#(bits)) e = newVector;

        e[0] = m[0];
        e[1] = m[1];
        e[2] = m[2];
        e[3] = m[3];
        e[4] = bf_add(-m[4], -helper3);
        e[5] = m[5];
        e[6] = bf_add(m[6], -helper3);
        e[7] = m[7];
        f_stages[5].enq(e);
    endrule

    //stage5
    rule rstage5;
        let e = f_stages[5].first; f_stages[5].deq;
        Vector#(8, Int#(bits)) f = newVector;
        f[0] = e[0];
        f[1] = e[1];
        f[2] = bf_add(e[2],  e[3]);
        f[3] = bf_add(e[3], -e[2]);
        f[4] = e[4];
        f[5] = bf_add(e[5], e[7]);
        f[6] = e[6];
        f[7] = bf_add(e[7], -e[5]);
        f_stages[6].enq(f);
    endrule

    //stage6
    rule rstage6;
        let f = f_stages[6].first; f_stages[6].deq;
        Vector#(8, Int#(bits)) g = newVector;
        g[0] = f[0];
        g[1] = f[1];
        g[2] = f[2];
        g[3] = f[3];
        g[4] = bf_add( f[4],  f[7]);
        g[5] = bf_add( f[5],  f[6]);
        g[6] = bf_add(-f[6],  f[5]);
        g[7] = bf_add( f[7], -f[4]);

        Vector#(8, Int#(bits)) out = newVector;

        //TODO: move scaling into dedicated stage
        if(scale_out) begin
            Vector#(8, Int#(bits)) t = newVector;
            t[0] = mul(g[0], s0_i);
            t[1] = mul(g[1], s4_i);
            t[2] = mul(g[2], s2_i);
            t[3] = mul(g[3], s6_i);
            t[4] = mul(g[4], s5_i);
            t[5] = mul(g[5], s1_i);
            t[6] = mul(g[6], s7_i);
            t[7] = mul(g[7], s3_i);
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

        f_out.enq(out);
    endrule

    method overflow = False;

    interface data = toGPServer(f_stages[0], f_out);

endmodule


endpackage