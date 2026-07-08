package CmodFullHDColorEncoder;

import Clocks :: *;

import BlueJPEG :: *;
import Types :: *;

(* synthesize, default_clock_osc="aclk", default_reset="aresetn", clock_prefix="" *)
module mkCmodFullHDColorJPEGEncoder#(Clock clk_dct)(BlueJPEG_ifc);

    //fast clock and associated reset
    let aclk    <- exposeCurrentClock;
    let aresetn <- exposeCurrentReset;

    let dct_reset <- mkResetSync(2, True, clk_dct);

    NumProxy#(1920) maximw = ?;
    NumProxy#(12)   fscale = ?;
    NumProxy#(16)   dpw = ?;

    let jpeg_cfg = BlueJPEGCfg_t {
        slow_clock : clk_dct,
        slow_reset : dct_reset.new_rst,
        _prx_miw   : maximw,
        _prx_dsc   : fscale,
        _prx_qsc   : fscale,
        _prx_dpw   : dpw,
        en_tiler   : True,
        en_chroma  : True
    };
    BlueJPEG_ifc ifc();
    mkBlueJPEG#(jpeg_cfg) __internal(ifc);

    return ifc;
endmodule

endpackage
