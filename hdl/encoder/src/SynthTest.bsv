package SynthTest;

import Clocks :: *;

import Util :: *;
import Types :: *;
import DCT1D :: *;
import DCT2D :: *;
import DUProc :: *;
import BlueJPEG :: *;
import DCT2D_Optimized :: *;
import ImageTilingEngine :: *;

module [Module] mkDCT1D_16b(DCT1D_ifc#(16));
    NumProxy#(12) f_scale = ?;
    DCT1D_ifc#(16) ifc();
    mkDCT1D#(f_scale, False, True) __int(ifc);
    return ifc;
endmodule


module [Module] mkDCT1D_12b(DCT1D_ifc#(12));
    NumProxy#(12) f_scale = ?;
    DCT1D_ifc#(12) ifc();
    mkDCT1D#(f_scale, False, True) __int(ifc);
    return ifc;
endmodule


module [Module] mkDCT1D_12b_rigid(DCT1D_ifc#(12));
    NumProxy#(12) f_scale = ?;
    DCT1D_ifc#(12) ifc();
    mkDCT1D_rigid#(f_scale, False, False) __int(ifc);
    return ifc;
endmodule

module [Module] mkDCT2D_Optimized_12b(DCT2DOpt_ifc#(12));
    NumProxy#(8) f_scale = ?;
    DCT2DOpt_ifc#(12) ifc();
    mkDCT2D_Opt#(f_scale, False, True, False, True) __int(ifc);
    return ifc;
endmodule

module [Module] mkDCT2D_Optimized_rigid(DCT2DOptRigid_ifc#(8));
    NumProxy#(12) f_scale = ?;
    DCT2DOptRigid_ifc#(8) ifc();
    mkDCT2D_Opt_rigid#(f_scale, False, True, False, False) __int(ifc);
    return ifc;
endmodule


module [Module] mkDCT2D_Optimized_14b(DCT2DOpt_ifc#(14));
    NumProxy#(12) f_scale = ?;
    DCT2DOpt_ifc#(14) ifc();
    mkDCT2D_Opt#(f_scale, False, True, False, True) __int(ifc);
    return ifc;
endmodule


module [Module] mkDUProc_16b(DUProcLegacy_t#(8, 16));

    //this module [Module] is used for utilization analysis
    //for simplicity, use the same clock for the DCT

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    NumProxy#(12) dct_scale     = ?;
    NumProxy#(12) quant_scale   = ?;

    let mcuproc_cfg = DUProcCfg {
        slow_clock       : clk,
        slow_reset       : rst,
        buffer_in        : True,
        _dct_scale       : dct_scale,
        scale_in_dct     : False,
        transpose_in_dct : False,
        _q_scale         : quant_scale,
        debug            : False,
        dct_safe_arith   : False
    };

    DUProcLegacy_t#(8, 16) ifc();
    mkDUProc#(mcuproc_cfg) __int(ifc);
    return ifc;
endmodule


module [Module] mkDUProc_Opt_8b(DUProc_t#(8));

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    NumProxy#(12) dct_scale     = ?;
    NumProxy#(12) quant_scale   = ?;

    let du_proc_cfg = DUProcCfg {
        slow_clock       : clk,
        slow_reset       : rst,
        buffer_in        : True,
        _dct_scale       : dct_scale,
        scale_in_dct     : False,
        transpose_in_dct : False,
        _q_scale         : quant_scale,
        debug            : False,
        dct_safe_arith   : False
    };

    DUProc_t#(8) ifc();
    mkDUProc_Opt#(du_proc_cfg) __int(ifc);
    return ifc;
endmodule


module [Module] mkImageTilingEngine_1920(ImageTilingEngine_ifc#(Bit#(8), 8, 8));
    NumProxy#(1920) max_width = ?;
    ImageTilingEngine_ifc#(Bit#(8), 8, 8) ifc();
    mkImageTilingEngine#(max_width, False) __int(ifc);
    return ifc;
endmodule

// (* synthesize *)
// module [Module] mkImageTilingEngine_2560(ImageTilingEngine_ifc#(Bit#(8), 8, 8));
//     NumProxy#(2560) max_width = ?;
//     ImageTilingEngine_ifc#(Bit#(8), 8, 8) ifc();
//     mkImageTilingEngine#(max_width, False) __int(ifc);
//     return ifc;
// endmodule

// (* synthesize *)
// module [Module] mkImageTilingEngine_3840(ImageTilingEngine_ifc#(Bit#(8), 8, 8));
//     NumProxy#(3840) max_width = ?;
//     ImageTilingEngine_ifc#(Bit#(8), 8, 8) ifc();
//     mkImageTilingEngine#(max_width, False) __int(ifc);
//     return ifc;
// endmodule

(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGTop_1920_12#(Clock dct_clock)(BlueJPEG_ifc);

    //fast clock and associated reset
    let aclk    <- exposeCurrentClock;
    let aresetn <- exposeCurrentReset;

    let dct_reset <- mkResetSync(2, True, dct_clock);

    NumProxy#(1920) maximw = ?;
    NumProxy#(12)   fscale = ?;
    NumProxy#(8)    pixel_width = ?;

    let jpeg_cfg = BlueJPEGCfg_t {
        slow_clock          : dct_clock,
        slow_reset          : dct_reset.new_rst,
        _prx_miw            : maximw,
        _prx_dsc            : fscale,
        _prx_qsc            : fscale,
        _prx_pixw           : pixel_width,
        en_tiler            : True,
        double_buffer_tiler : True,
        en_chroma           : True
    };
    BlueJPEG_ifc ifc();
    mkBlueJPEG#(jpeg_cfg) __internal(ifc);

    return ifc;
endmodule


(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGTop_2560_12_12#(Clock dct_clock)(BlueJPEG_ifc);

    //fast clock and associated reset
    let aclk    <- exposeCurrentClock;
    let aresetn <- exposeCurrentReset;

    let dct_reset <- mkResetSync(2, True, dct_clock);

    NumProxy#(2560) maximw = ?;
    NumProxy#(12)   fscale = ?;
    NumProxy#(8)    pixel_width = ?;

    let jpeg_cfg = BlueJPEGCfg_t {
        slow_clock          : dct_clock,
        slow_reset          : dct_reset.new_rst,
        _prx_miw            : maximw,
        _prx_dsc            : fscale,
        _prx_qsc            : fscale,
        _prx_pixw           : pixel_width,
        en_tiler            : True,
        double_buffer_tiler : False,
        en_chroma           : True
    };
    BlueJPEG_ifc ifc();
    mkBlueJPEG#(jpeg_cfg) __internal(ifc);

    return ifc;
endmodule


(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGGrayTop_1920_12_12#(Clock dct_clock)(BlueJPEG_ifc);

    //fast clock and associated reset
    let aclk    <- exposeCurrentClock;
    let aresetn <- exposeCurrentReset;

    let dct_reset <- mkResetSync(2, True, dct_clock);

    NumProxy#(1920) maximw = ?;
    NumProxy#(12)   fscale = ?;
    NumProxy#(8)    pixel_width = ?;

    let jpeg_cfg = BlueJPEGCfg_t {
        slow_clock          : dct_clock,
        slow_reset          : dct_reset.new_rst,
        _prx_miw            : maximw,
        _prx_dsc            : fscale,
        _prx_qsc            : fscale,
        _prx_pixw           : pixel_width,
        en_tiler            : True,
        double_buffer_tiler : False,
        en_chroma           : False
    };
    BlueJPEG_ifc ifc();
    mkBlueJPEG#(jpeg_cfg) __internal(ifc);

    return ifc;
endmodule


(* default_clock_osc="aclk", default_reset="aresetn" *)
module [Module] mkBlueJPEGGrayTop_720_12_12#(Clock dct_clock)(BlueJPEG_ifc);

    //fast clock and associated reset
    let aclk    <- exposeCurrentClock;
    let aresetn <- exposeCurrentReset;

    let dct_reset <- mkResetSync(2, True, dct_clock);

    NumProxy#(720) maximw = ?;
    NumProxy#(12)   fscale = ?;
    NumProxy#(8)    pixel_width = ?;

    let jpeg_cfg = BlueJPEGCfg_t {
        slow_clock          : dct_clock,
        slow_reset          : dct_reset.new_rst,
        _prx_miw            : maximw,
        _prx_dsc            : fscale,
        _prx_qsc            : fscale,
        _prx_pixw           : pixel_width,
        en_tiler            : True,
        double_buffer_tiler : False,
        en_chroma           : False
    };
    BlueJPEG_ifc ifc();
    mkBlueJPEG#(jpeg_cfg) __internal(ifc);

    return ifc;
endmodule


endpackage
