package JpegEncoderResource;

import Clocks :: *;

import BlueJPEG :: *;
import Types :: *;

//standalone version of the UDP system's encoder, including its AXI-Lite register map
(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkJpegEncoderResource(BlueJPEG_ifc);
    let                             clk <- exposeCurrentClock;
    let                             rst <- exposeCurrentReset;
    BlueJPEGCfg_t#(1920, 12, 12, 8) cfg = BlueJPEGCfg_t {
        slow_clock         : clk,
        slow_reset         : rst,
        _prx_miw           : ?,
        _prx_dsc           : ?,
        _prx_qsc           : ?,
        _prx_pixw          : ?,
        en_tiler           : True,
        double_buffer_tiler: True,
        en_chroma          : True,
        shallow_dct        : False
    };
    let i_enc <- mkBlueJPEG(cfg);
    return i_enc;
endmodule

endpackage
