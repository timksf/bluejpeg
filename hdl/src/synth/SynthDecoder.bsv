package SynthDecoder;

import Clocks :: *;

import Types :: *;
import BlueJPEGDec :: *;

//out-of-context decoder variants, same clocking as the encoder tops in SynthTest
//aclk carries the stream side and dct_clock the IDCT

module [Module] mkBlueJPEGDecTop_1920_cfg#(Clock dct_clock, Bool en_huff_lookahead)(BlueJPEGDec_ifc);

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
        en_huff_lookahead:     en_huff_lookahead
    };
    BlueJPEGDec_ifc ifc();
    mkBlueJPEGDec#(cfg) __internal(ifc);

    return ifc;
endmodule

(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGDecTop_1920#(Clock dct_clock)(BlueJPEGDec_ifc);
    let ifc <- mkBlueJPEGDecTop_1920_cfg(dct_clock, False);
    return ifc;
endmodule

//with Huffman lookahead tables
(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGDecTop_1920_look#(Clock dct_clock)(BlueJPEGDec_ifc);
    let ifc <- mkBlueJPEGDecTop_1920_cfg(dct_clock, True);
    return ifc;
endmodule

endpackage
