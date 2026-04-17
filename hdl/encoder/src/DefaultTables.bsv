package DefaultTables;

import Real :: *;
import Array :: *;
import Vector :: *;
import BuildVector :: *;

import Types :: *;

//-------------------------------------------------------------------
// Standard JPEG Quantization tables (Annex K.1, ITU-T T.81)
//-------------------------------------------------------------------

//quantization defaults
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

//AAN scaling factors combined with quantization, evaluated at compile time
//result: round(2^scale_bits * s[row] * s[col] / q[i])
//if transposed==True, indices are transposed so the table matches a transposed DCT output
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

//-------------------------------------------------------------------
// Standard JPEG Huffman tables (Annex K.3, ITU-T T.81)
//-------------------------------------------------------------------

// BITS tables (number of codes per code-length 1..16, stored at indices 0..15)
Vector#(16, UInt#(8)) std_dc_luma_bits = vec(
    0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0
);
Vector#(16, UInt#(8)) std_dc_chroma_bits = vec(
    0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0
);
Vector#(16, UInt#(8)) std_ac_luma_bits = vec(
    0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125
);
Vector#(16, UInt#(8)) std_ac_chroma_bits = vec(
    0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119
);

// HUFFVAL: DC tables are simply {0,1,2,...,11}
Vector#(12, UInt#(8)) std_dc_val = vec(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);

// HUFFVAL: AC luminance (162 symbols, Table K.5)
UInt#(8) std_ac_luma_val_arr[162] = {
    'h01, 'h02, 'h03, 'h00, 'h04, 'h11, 'h05, 'h12,
    'h21, 'h31, 'h41, 'h06, 'h13, 'h51, 'h61, 'h07,
    'h22, 'h71, 'h14, 'h32, 'h81, 'h91, 'ha1, 'h08,
    'h23, 'h42, 'hb1, 'hc1, 'h15, 'h52, 'hd1, 'hf0,
    'h24, 'h33, 'h62, 'h72, 'h82, 'h09, 'h0a, 'h16,
    'h17, 'h18, 'h19, 'h1a, 'h25, 'h26, 'h27, 'h28,
    'h29, 'h2a, 'h34, 'h35, 'h36, 'h37, 'h38, 'h39,
    'h3a, 'h43, 'h44, 'h45, 'h46, 'h47, 'h48, 'h49,
    'h4a, 'h53, 'h54, 'h55, 'h56, 'h57, 'h58, 'h59,
    'h5a, 'h63, 'h64, 'h65, 'h66, 'h67, 'h68, 'h69,
    'h6a, 'h73, 'h74, 'h75, 'h76, 'h77, 'h78, 'h79,
    'h7a, 'h83, 'h84, 'h85, 'h86, 'h87, 'h88, 'h89,
    'h8a, 'h92, 'h93, 'h94, 'h95, 'h96, 'h97, 'h98,
    'h99, 'h9a, 'ha2, 'ha3, 'ha4, 'ha5, 'ha6, 'ha7,
    'ha8, 'ha9, 'haa, 'hb2, 'hb3, 'hb4, 'hb5, 'hb6,
    'hb7, 'hb8, 'hb9, 'hba, 'hc2, 'hc3, 'hc4, 'hc5,
    'hc6, 'hc7, 'hc8, 'hc9, 'hca, 'hd2, 'hd3, 'hd4,
    'hd5, 'hd6, 'hd7, 'hd8, 'hd9, 'hda, 'he1, 'he2,
    'he3, 'he4, 'he5, 'he6, 'he7, 'he8, 'he9, 'hea,
    'hf1, 'hf2, 'hf3, 'hf4, 'hf5, 'hf6, 'hf7, 'hf8,
    'hf9, 'hfa
};
Vector#(162, UInt#(8)) std_ac_luma_val = arrayToVector(std_ac_luma_val_arr);

// HUFFVAL: AC chrominance (162 symbols, Table K.6)
UInt#(8) std_ac_chroma_val_arr[162] = {
    'h00, 'h01, 'h02, 'h03, 'h11, 'h04, 'h05, 'h21,
    'h31, 'h06, 'h12, 'h41, 'h51, 'h07, 'h61, 'h71,
    'h13, 'h22, 'h32, 'h81, 'h08, 'h14, 'h42, 'h91,
    'ha1, 'hb1, 'hc1, 'h09, 'h23, 'h33, 'h52, 'hf0,
    'h15, 'h62, 'h72, 'hd1, 'h0a, 'h16, 'h24, 'h34,
    'he1, 'h25, 'hf1, 'h17, 'h18, 'h19, 'h1a, 'h26,
    'h27, 'h28, 'h29, 'h2a, 'h35, 'h36, 'h37, 'h38,
    'h39, 'h3a, 'h43, 'h44, 'h45, 'h46, 'h47, 'h48,
    'h49, 'h4a, 'h53, 'h54, 'h55, 'h56, 'h57, 'h58,
    'h59, 'h5a, 'h63, 'h64, 'h65, 'h66, 'h67, 'h68,
    'h69, 'h6a, 'h73, 'h74, 'h75, 'h76, 'h77, 'h78,
    'h79, 'h7a, 'h82, 'h83, 'h84, 'h85, 'h86, 'h87, 
    'h88, 'h89, 'h8a, 'h92, 'h93, 'h94, 'h95, 'h96, 
    'h97, 'h98, 'h99, 'h9a, 'ha2, 'ha3, 'ha4, 'ha5, 
    'ha6, 'ha7, 'ha8, 'ha9, 'haa, 'hb2, 'hb3, 'hb4, 
    'hb5, 'hb6, 'hb7, 'hb8, 'hb9, 'hba, 'hc2, 'hc3, 
    'hc4, 'hc5, 'hc6, 'hc7, 'hc8, 'hc9, 'hca, 'hd2, 
    'hd3, 'hd4, 'hd5, 'hd6, 'hd7, 'hd8, 'hd9, 'hda, 
    'he2, 'he3, 'he4, 'he5, 'he6, 'he7, 'he8, 'he9, 
    'hea, 'hf2, 'hf3, 'hf4, 'hf5, 'hf6, 'hf7, 'hf8, 
    'hf9, 'hfa
};
Vector#(162, UInt#(8)) std_ac_chroma_val = arrayToVector(std_ac_chroma_val_arr);

endpackage