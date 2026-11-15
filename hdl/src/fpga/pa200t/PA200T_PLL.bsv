package PA200T_PLL;

import Clocks :: *;
import DefaultValue :: *;
import BlueXLNX :: *;

interface PA200T_PLL_ifc;
    interface Clock clk_sys;   //50 MHz, bus, JTAG bridge, encoder and pattern source
    interface Clock clk_uart;  //125 MHz, UART
    interface Reset rst_sys;
    interface Reset rst_uart;
endinterface

/*
 * Both outputs come from one PLL fed by the 200 MHz board clock. Each reset is held
 * until the PLL locks and is released synchronously to its clock. The two domains only
 * meet in the dual-clock FIFO and the synchronized UART divider register.
 */
(* no_default_clock *)
module mkPA200T_PLL#(Clock clk_200)(PA200T_PLL_ifc);
    //VCO 200 * 5 = 1000 MHz, 1000 / 20 = 50 MHz and 1000 / 8 = 125 MHz
    PLLE2_ADV_Config cfg_pll = defaultValue;
    cfg_pll.p_CLKIN1_PERIOD   = 5.0;
    cfg_pll.p_CLKFBOUT_MULT   = 5;
    cfg_pll.p_CLKOUT0_DIVIDE  = 20;
    cfg_pll.p_CLKOUT1_DIVIDE  = 8;
    cfg_pll.p_COMPENSATION    = "INTERNAL";
    cfg_pll.p_IS_RST_INVERTED = 1;

    Reset              rst_board        <- exposeCurrentReset;
    ClockWire_ifc      i_feedback       <- mkClockWire(clocked_by clk_200);
    PLLE2_ADV_ifc      i_pll            <- mkPLLE2_ADV(cfg_pll, clk_200, noClock, i_feedback.clk, clk_200, clocked_by clk_200);
    ReadOnly#(Bit#(1)) i_feedback_value <- mkClockValue(i_pll.clkfbout);
    Clock              clk_50           <- mkBUFGClock(i_pll.clkout0);
    Clock              clk_125          <- mkBUFGClock(i_pll.clkout1);

    ResetWire_ifc i_lock_reset <- mkResetWire(i_pll.locked);
    Reset         rst_source   <- mkResetEither(rst_board, i_lock_reset.rst, clocked_by clk_200);
    Reset         rst_50       <- mkAsyncReset(2, rst_source, clk_50);
    Reset         rst_125      <- mkAsyncReset(2, rst_source, clk_125);

    rule r_pll_inputs;
        i_feedback.drive(i_feedback_value);
        i_pll.clkinsel(1);
        i_pll.pwrdwn(0);
        i_pll.daddr(0);
        i_pll.den(0);
        i_pll.d_i(0);
        i_pll.dwe(0);
    endrule

    interface clk_sys  = clk_50;
    interface clk_uart = clk_125;
    interface rst_sys  = rst_50;
    interface rst_uart = rst_125;
endmodule

endpackage
