package SynthDecoder;

import Clocks :: *;

import Types :: *;
import BlueJPEGDec :: *;

//out-of-context decoder variants, same clocking as the encoder tops in SynthTest
//aclk carries the stream side and dct_clock the IDCT

module [Module] mkBlueJPEGDecTop_1920_cfg#(
    Clock       dct_clock,
    Bool        en_huff_lookahead,
    ChromaSub_t max_chroma_sub,
    Bool        shallow_idct,
    Bool        fixed_huff_tables
)(BlueJPEGDec_ifc);

    let dct_reset <- mkResetSync(2, True, dct_clock);

    BlueJPEGDecCfg_t#(1920, 13, 8, 8) cfg = BlueJPEGDecCfg_t {
        slow_clock:            dct_clock,
        slow_reset:            dct_reset.new_rst,
        _prx_miw:              ?,
        _prx_dsc:              ?,
        _prx_qsc:              ?,
        _prx_pixw:             ?,
        en_untiler:            True,
        double_buffer_untiler: True,
        en_chroma:             True,
        en_huff_lookahead:     en_huff_lookahead,
        max_chroma_sub:        max_chroma_sub,
        shallow_idct:          shallow_idct,
        fixed_huff_tables:     fixed_huff_tables
    };
    BlueJPEGDec_ifc ifc();
    mkBlueJPEGDec#(cfg) __internal(ifc);

    return ifc;
endmodule

(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGDecTop_1920#(Clock dct_clock)(BlueJPEGDec_ifc);
    let ifc <- mkBlueJPEGDecTop_1920_cfg(dct_clock, False, Sub422, False, False);
    return ifc;
endmodule

//two register stages per IDCT pass
(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGDecTop_1920_shallow#(Clock dct_clock)(BlueJPEGDec_ifc);
    let ifc <- mkBlueJPEGDecTop_1920_cfg(dct_clock, False, Sub422, True, False);
    return ifc;
endmodule

//standard Huffman tables as constants
(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGDecTop_1920_fixed#(Clock dct_clock)(BlueJPEGDec_ifc);
    let ifc <- mkBlueJPEGDecTop_1920_cfg(dct_clock, False, Sub422, False, True);
    return ifc;
endmodule

//both resource options
(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGDecTop_1920_lean#(Clock dct_clock)(BlueJPEGDec_ifc);
    let ifc <- mkBlueJPEGDecTop_1920_cfg(dct_clock, False, Sub422, True, True);
    return ifc;
endmodule

//4:4:4 only, the configuration before subsampling support
(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGDecTop_1920_444#(Clock dct_clock)(BlueJPEGDec_ifc);
    let ifc <- mkBlueJPEGDecTop_1920_cfg(dct_clock, False, Sub444, False, False);
    return ifc;
endmodule

//up to 4:2:0, with a 16-line luma buffer
(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGDecTop_1920_420#(Clock dct_clock)(BlueJPEGDec_ifc);
    let ifc <- mkBlueJPEGDecTop_1920_cfg(dct_clock, False, Sub420, False, False);
    return ifc;
endmodule

//with Huffman lookahead tables
(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGDecTop_1920_look#(Clock dct_clock)(BlueJPEGDec_ifc);
    let ifc <- mkBlueJPEGDecTop_1920_cfg(dct_clock, True, Sub422, False, False);
    return ifc;
endmodule

endpackage
