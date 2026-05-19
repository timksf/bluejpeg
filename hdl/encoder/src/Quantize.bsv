package Quantize;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import Connectable :: *;
import BuildVector :: *;
import SpecialFIFOs :: *;
import ClientServer :: *;
import Real :: *;

import Util :: *;
import Types :: *;

Vector#(64, Integer) std_LUMA_QUANT_c = vec(
    16, 11, 10, 16,  24,  40,  51,  61,
    12, 12, 14, 19,  26,  58,  60,  55,
    14, 13, 16, 24,  40,  57,  69,  56,
    14, 17, 22, 29,  51,  87,  80,  62,
    18, 22, 37, 56,  68, 109, 103,  77,
    24, 35, 55, 64,  81, 104, 113,  92,
    49, 64, 78, 87, 103, 121, 120, 101,
    72, 92, 95, 98, 112, 100, 103,  99
);

Vector#(64, Integer) std_CHROMA_QUANT_c = vec(
    17, 18, 24, 47, 99, 99, 99, 99,
    18, 21, 26, 66, 99, 99, 99, 99,
    24, 26, 56, 99, 99, 99, 99, 99,
    47, 66, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99
);

function Vector#(64, Integer) quant_mult(Vector#(64, Integer) q_table, NumProxy#(scale_bits) p, Bool transposed);
    Vector#(8, Real) s = newVector;
    s[0] = 1.0 / (2.0 * sqrt(2.0));
    s[1] = 1.0 / (4.0 * cos(1.0 * pi / 16.0));
    s[2] = 1.0 / (4.0 * cos(2.0 * pi / 16.0));
    s[3] = 1.0 / (4.0 * cos(3.0 * pi / 16.0));
    s[4] = 1.0 / (4.0 * cos(4.0 * pi / 16.0));
    s[5] = 1.0 / (4.0 * cos(5.0 * pi / 16.0));
    s[6] = 1.0 / (4.0 * cos(6.0 * pi / 16.0));
    s[7] = 1.0 / (4.0 * cos(7.0 * pi / 16.0));

    Vector#(64, Integer) res = newVector;
    Real scale = 2.0 ** fromInteger(valueof(scale_bits));
    for(Integer i=0; i<64; i=i+1) begin
        Integer idx = transposed ? ((i%8)*8 + i/8) : i;
        res[i] = round(scale * s[idx/8] * s[idx%8] / fromInteger(q_table[idx]));
    end
    return res;
endfunction

interface Quant_ifc#(numeric type bits);
    method Action rewind();
    interface Put#(PixType_t) du_mode;
    interface Client#(QuantTableIdx_t, Int#(32)) qtable;
    interface Server#(Int#(bits), Int#(bits)) data;
endinterface

module mkQuantize#(NumProxy#(bits_frac) f_scale, Bool buffer_in, Bool aan_scaling, Bool transposed)(Quant_ifc#(bits)) 
    provisos(
        Add#(bits_frac, 2, coeff_bits),
        Add#(bits, coeff_bits, bits_mul),
        Add#(a__, bits_frac, 32)         //bits_frac <= 32
    );

    FIFO#(Int#(bits)) f_i;
    FIFO#(Int#(bits)) f_o <- mkPipelineFIFO;

    if(buffer_in)
        f_i <- mkPipelineFIFO;
    else 
        f_i <- mkBypassFIFO;

    Reg#(Bit#(6))   rg_pxcnt    <- mkReg(0);
    FIFO#(PixType_t) f_mode     <- mkSizedFIFO(4);

    Vector#(64, Integer) luma_mult;
    Vector#(64, Integer) chroma_mult;
    if (aan_scaling) begin
        luma_mult   = quant_mult(std_LUMA_QUANT_c,   f_scale, transposed);
        chroma_mult = quant_mult(std_CHROMA_QUANT_c, f_scale, transposed);
    end else begin
        luma_mult   = std_LUMA_QUANT_c;
        chroma_mult = std_CHROMA_QUANT_c;
    end

    function mul = scaled_mul_s(True, f_scale);

    rule rquant;
        let val = f_i.first;
        f_i.deq;
        
        Integer mult = (f_mode.first == Luma) ? luma_mult[rg_pxcnt] : chroma_mult[rg_pxcnt];

        Int#(bits) prod = mul(val, mult);

        f_o.enq(truncate(prod));
        if (rg_pxcnt == 63) f_mode.deq;
        rg_pxcnt <= rg_pxcnt + 1;
    endrule

    method Action rewind();
        rg_pxcnt <= 0;
        f_mode.clear;
    endmethod

    interface du_mode = toPut(f_mode);
    interface data    = toGPServer(f_i, f_o);

endmodule

//runtime table variant
//should have combinational table connection
module mkQuantize_RT#(NumProxy#(bits_frac) f_scale, Bool buffer_in)(Quant_ifc#(bits))
    provisos(
        Add#(bits_frac, 2, coeff_bits),
        Add#(bits, coeff_bits, bits_mul),
        Add#(a__, bits_frac, 32)         //bits_frac <= 32
    );

    FIFO#(Int#(bits)) f_i;
    FIFO#(Int#(bits)) f_o <- mkPipelineFIFO;

    if(buffer_in)
        f_i <- mkPipelineFIFO;
    else 
        f_i <- mkBypassFIFO;

    Reg#(Bit#(6))   rg_pxcnt  <- mkReg(0);
    FIFO#(PixType_t) f_mode   <- mkSizedFIFO(4);

    //combinatorial table lookup
    Wire#(QuantTableIdx_t) w_tableidx <- mkWire;
    Wire#(Int#(32)) w_mult <- mkWire;

    rule rtable_read;
        w_tableidx <= QuantTableIdx_t { pt: f_mode.first, idx: rg_pxcnt };
    endrule

    function qmul = scaled_mul_rt(f_scale, True);

    rule rquant;
        let val = f_i.first;
        f_i.deq;

        Int#(bits_frac) mult = truncate(w_mult);
        Int#(bits) prod = qmul(val, mult);

        f_o.enq(prod);
        if (rg_pxcnt == 63) f_mode.deq;
        rg_pxcnt <= rg_pxcnt + 1;
    endrule

    method Action rewind();
        rg_pxcnt <= 0;
        f_mode.clear;
    endmethod
    
    interface du_mode   = toPut(f_mode);
    interface qtable    = toGPClient(asReg(w_tableidx), asReg(w_mult));
    interface data      = toGPServer(f_i, f_o);

endmodule


endpackage