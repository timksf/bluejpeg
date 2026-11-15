package PA200T_UDP_PLL;

import Clocks :: *;
import DefaultValue :: *;

import BlueXLNX :: *;

interface PA200T_UDP_PLL_ifc;
    interface Clock clk_125;
    interface Clock clk_125_90;
    interface Clock clk_bram;
    interface Clock clk_dct;
    interface Clock clk_app;
    interface Reset rst_125;
    interface Reset rst_bram;
    interface Reset rst_200;
endinterface

(* no_default_clock *)
module mkPA200T_UDP_PLL#(Clock clk_200)(PA200T_UDP_PLL_ifc);
    //200 * 5 = 1000 MHz VCO, 125 MHz GTX and 83.333 MHz BRAM test clock
    PLLE2_ADV_Config cfg = defaultValue;
    cfg.p_CLKIN1_PERIOD   = 5.0;
    cfg.p_CLKFBOUT_MULT   = 5;
    cfg.p_CLKOUT0_DIVIDE  = 8;
    cfg.p_CLKOUT1_DIVIDE  = 8;
    cfg.p_CLKOUT1_PHASE   = 90.0;
    cfg.p_CLKOUT2_DIVIDE  = 12;
    cfg.p_CLKOUT3_DIVIDE  = 40;
    cfg.p_CLKOUT4_DIVIDE  = 5;
    cfg.p_COMPENSATION    = "INTERNAL";
    cfg.p_IS_RST_INVERTED = 1;
    let rst_board  <- exposeCurrentReset;
    let i_feedback <- mkClockWire(clocked_by clk_200);
    let i_pll      <- mkPLLE2_ADV(cfg, clk_200, noClock, i_feedback.clk, clk_200, clocked_by clk_200);
    let feedback   <- mkClockValue(i_pll.clkfbout);
    let clk_gtx    <- mkBUFGClock(i_pll.clkout0);
    let clk_gtx90  <- mkBUFGClock(i_pll.clkout1);
    let clk_sys    <- mkBUFGClock(i_pll.clkout2);
    let clk_slow   <- mkBUFGClock(i_pll.clkout3);
    let clk_fast   <- mkBUFGClock(i_pll.clkout4);
    let i_lock     <- mkResetWire(i_pll.locked);
    let rst_source <- mkResetEither(rst_board, i_lock.rst, clocked_by clk_200);
    let rst_gtx    <- mkAsyncReset(2, rst_source, clk_gtx);
    let rst_sys    <- mkAsyncReset(2, rst_source, clk_sys);
    let rst_ref    <- mkAsyncReset(16, rst_source, clk_200);
    rule r_inputs;
        i_feedback.drive(feedback);
        i_pll.clkinsel(1);
        i_pll.pwrdwn(0);
        i_pll.daddr(0);
        i_pll.den(0);
        i_pll.d_i(0);
        i_pll.dwe(0);
    endrule
    interface clk_125    = clk_gtx;
    interface clk_125_90 = clk_gtx90;
    interface clk_bram   = clk_sys;
    interface clk_dct    = clk_slow;
    interface clk_app    = clk_fast;
    interface rst_125    = rst_gtx;
    interface rst_bram   = rst_sys;
    interface rst_200    = rst_ref;
endmodule

endpackage
