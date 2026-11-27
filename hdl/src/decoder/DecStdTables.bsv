package DecStdTables;

import Vector :: *;

import DefaultTables :: *;
import DecoderTypes :: *;

/*
 * The standard Huffman tables of T.81 Annex K.3 in the forms the decoder
 * uses, all evaluated at elaboration from the encoder's DefaultTables. Tables
 * are indexed {ac, id} like in DecTableStorage, with id 0 the luminance and
 * id 1 the chrominance tables:
 *
 *   0  DC luminance    1  DC chrominance    2  AC luminance    3  AC chrominance
 */

//BITS, the number of codes of each length 1..16
function Vector#(16, UInt#(8)) std_huff_bits(Integer t);
    case(t)
        0:       return std_dc_luma_bits;
        1:       return std_dc_chroma_bits;
        2:       return std_ac_luma_bits;
        default: return std_ac_chroma_bits;
    endcase
endfunction

//HUFFVAL, unused entries read as zero
function Vector#(256, Bit#(8)) std_huff_vals(Integer t);
    Vector#(256, Bit#(8)) v = replicate(0);
    for(Integer i = 0; i < 256; i = i + 1) begin
        if(t < 2 && i < 12)        v[i] = pack(std_dc_val[i]);
        else if(t == 2 && i < 162) v[i] = pack(std_ac_luma_val[i]);
        else if(t == 3 && i < 162) v[i] = pack(std_ac_chroma_val[i]);
    end
    return v;
endfunction

//LIMIT(l) and OFFSET(l) as DecTableStorage derives them from a DHT segment
function HuffLimits_t std_huff_limits(Integer t);
    Vector#(16, UInt#(8)) bits = std_huff_bits(t);
    HuffLimits_t          lim  = unpack(0);
    UInt#(17)             code = 0;
    Bit#(8)               k    = 0;
    for(Integer l = 0; l < 16; l = l + 1) begin
        UInt#(17) code_end = code + extend(bits[l]);
        lim.limit[l]  = code_end;
        lim.offset[l] = k - truncate(pack(code));
        code = code_end << 1;
        k    = k + pack(bits[l]);
    end
    return lim;
endfunction

//CRC-32 (polynomial 0x04C11DB7, MSB first) of one byte, the DHT check of fixed tables runs it over BITS and HUFFVAL
function Bit#(32) crc32_byte(Bit#(32) crc, Bit#(8) b);
    Bit#(32) c = crc ^ (zeroExtend(b) << 24);
    for(Integer i = 0; i < 8; i = i + 1)
        c = c[31] == 1 ? (c << 1) ^ 'h04C11DB7 : c << 1;
    return c;
endfunction

Bit#(32) crc32_init = 'hFFFFFFFF;

//CRC of the sixteen BITS counts followed by the HUFFVAL entries of a standard table
function Bit#(32) std_huff_crc(Integer t);
    Vector#(16, UInt#(8))  bits  = std_huff_bits(t);
    Vector#(256, Bit#(8))  vals  = std_huff_vals(t);
    Bit#(32)               crc   = crc32_init;
    UInt#(9)               total = 0;
    for(Integer l = 0; l < 16; l = l + 1) begin
        crc   = crc32_byte(crc, pack(bits[l]));
        total = total + extend(bits[l]);
    end
    for(Integer i = 0; i < 256; i = i + 1)
        if(fromInteger(i) < total) crc = crc32_byte(crc, vals[i]);
    return crc;
endfunction

//lookahead entry for the top HuffLookBits window bits b, invalid when the code is longer
function HuffLook_t std_huff_look(Integer t, Bit#(HuffLookBits) b);
    Vector#(16, UInt#(8))  bits = std_huff_bits(t);
    Vector#(256, Bit#(8))  vals = std_huff_vals(t);
    HuffLook_t             e    = unpack(0);
    UInt#(17)              code = 0;
    UInt#(9)               k    = 0;
    Integer                n_lb = valueOf(HuffLookBits);
    for(Integer l = 1; l <= n_lb; l = l + 1) begin
        UInt#(17) n   = extend(bits[l - 1]);
        UInt#(17) top = extend(unpack(b >> (n_lb - l)));
        if(!e.valid && top >= code && top < code + n) begin
            Bit#(8) sym = vals[k + truncate(top - code)];
            e = HuffLook_t {
                valid: True,
                len:   fromInteger(l),
                used:  fromInteger(l) + extend(unpack(sym[3:0])),
                sym:   sym
            };
        end
        k    = k + truncate(n);
        code = (code + n) << 1;
    end
    return e;
endfunction

endpackage
