package PA200T_JPEG;

import Clocks :: *;
import Connectable :: *;
import DefaultValue :: *;
import Axi4Lite :: *;
import Axi4LiteAddrMap :: *;
import Axi4LiteRegSlice :: *;
import BlueAddrMap :: *;
import BlueAXI :: *;
import BlueJ :: *;
import BlueXLNX :: *;

import JpegTestSystem :: *;
import PA200T_JTAG :: *;
import PA200T_PLL :: *;
import PA200T_Pins :: *;

(* always_enabled *)
interface PA200T_JPEG_ifc;
    //JTAG TAP on the header pins, the bus master for all registers
    (* prefix = "" *)
    method Action tms((* port = "TMS" *) Bit#(1) t);
    (* prefix = "" *)
    method Action tdi((* port = "TDI" *) Bit#(1) t);
    (* prefix = "", result = "TDO" *)
    method Bit#(1) tdo;

    //pins driven from the PLL domains leave through null crossings and carry no clock
    //LED[0]: encoder interrupt, LED[1]: JTAG LED control register
    (* result = "LED" *)
    method Bit#(2) leds;

    //USB-UART, JPEG output
    (* prefix = "uart" *)
    method Action rx((* port = "rx" *) Bit#(1) value);
    (* result = "uart_tx" *)
    method Bit#(1) tx;
endinterface

//board logic below the clock and pad wrapper, the receive pad lives in the top
interface PA200T_JPEG_Core_ifc;
    method Action  tms(Bit#(1) t);
    method Action  tdi(Bit#(1) t);
    method Bit#(1) tdo;
    method Bit#(2) leds;
    method Bit#(1) tx;
endinterface

/*
 * Bus map of the JTAG master. Both targets are BlueCSR maps that decode from offset 0,
 * the bus hands them region-local addresses.
 */
module [AddrMapCtx_t#(32, Axi4LiteSlaveFab_ifc#(32, 32))] pa200t_jpeg_addr_map#(Axi4LiteSlaveFab_ifc#(32, 32) test, Axi4LiteSlaveFab_ifc#(32, 32) jpeg)(Empty);
    addr_map_def("PA200T JPEG AXI4-Lite");
    addr_map_target('h0000_0000, 'h1000, "TEST", test);
    addr_map_target('h0000_2000, 'h2000, "JPEG", jpeg);
endmodule

//drives the UART receive input from the pin, instantiated in the UART clock and reset domain
module mkUartRxPin#(Bit#(1) pin, JpegTestSystem_ifc sys)(Empty);
    (* fire_when_enabled, no_implicit_conditions *)
    rule r_uart_rx;
        sys.uart_rx(pin);
    endrule
endmodule

(* no_default_clock *)
module [Module] mkPA200T_JPEG_Top#(Clock tck, Clock clk_p, Clock clk_n)(PA200T_JPEG_ifc);
    //the receive pad needs a top-level clock for its method, the board clock pin is used for bookkeeping only
    PadIn_ifc            i_rx   <- mkPadIn(clk_p);
    PA200T_JPEG_Core_ifc i_core <- wrap_diff_clk(mkPA200T_JPEG_Clocks(tck, i_rx.i), clk_p, clk_n);

    method tms  = i_core.tms;
    method tdi  = i_core.tdi;
    method tdo  = i_core.tdo;
    method leds = i_core.leds;
    method rx   = i_rx.pad;
    method tx   = i_core.tx;
endmodule

//takes the 200 MHz board clock, the design runs on the PLL's 50 MHz and the UART on its 125 MHz
module [Module] mkPA200T_JPEG_Clocks#(Clock tck, Bit#(1) uart_rx)(PA200T_JPEG_Core_ifc);
    Clock                clk_200 <- exposeCurrentClock;
    PA200T_PLL_ifc       i_pll   <- mkPA200T_PLL(clk_200);
    PA200T_JPEG_Core_ifc i_core  <- mkPA200T_JPEG(tck, i_pll.clk_uart, i_pll.rst_uart, uart_rx, clocked_by i_pll.clk_sys, reset_by i_pll.rst_sys);
    return i_core;
endmodule

module [Module] mkPA200T_JPEG#(Clock tck, Clock clk_uart, Reset rst_uart, Bit#(1) uart_rx)(PA200T_JPEG_Core_ifc);
    Clock clk_sys  <- exposeCurrentClock;
    Reset rst_sys  <- exposeCurrentReset;
    Reset rst_jtag <- mkAsyncResetFromCR(2, tck);

    JTAGSystem_ifc#(PA200T_JTAG_ifc) i_jtag <- mkPA200T_JTAG_NATIVE(clk_sys, rst_sys, clocked_by tck, reset_by rst_jtag);
    JpegTestSystem_ifc               i_sys  <- mkJpegTestSystem(clk_uart, rst_uart);

    //JTAG-to-AXI master -> address-decoded register bus
    Axi4LiteBusCfg_t cfg_bus = defaultValue;
    cfg_bus.upstream_cut = axi4_lite_slice_request;
    cfg_bus.local_addr   = True;

    AddrMapCollected_t#(2, Axi4LiteSlaveFab_ifc#(32, 32), Empty) addr_map <- collect_addr_map(pa200t_jpeg_addr_map(axi4_lite_slave_fab(i_sys.s_test_rd, i_sys.s_test_wr), axi4_lite_slave_fab(i_sys.s_jpeg_rd, i_sys.s_jpeg_wr)));
    AddrMapBus_ifc#(2, Axi4LiteSlaveFab_ifc#(32, 32), Empty)     i_bus    <- mkAddrMapBus(cfg_bus, addr_map);

    messageM(doc_addr_map(addr_map).text);
    mkConnection(axi4_lite_master_fab(i_jtag.device_ifc.m_axil_rd, i_jtag.device_ifc.m_axil_wr), i_bus.up);

    //output pins are asynchronous to the board anyway
    ReadOnly#(Bit#(2)) i_leds <- mkNullCrossingWire(noClock, {i_jtag.device_ifc.leds[1], pack(i_sys.irq)});
    ReadOnly#(Bit#(1)) i_tx   <- mkNullCrossingWire(noClock, i_sys.uart_tx, clocked_by clk_uart, reset_by rst_uart);

    //the receive pin has neither clock nor reset, the UART synchronizes it
    mkUartRxPin(uart_rx, i_sys, clocked_by clk_uart, reset_by rst_uart);

    method tms  = i_jtag.tms;
    method tdi  = i_jtag.tdi;
    method tdo  = i_jtag.tdo;
    method leds = i_leds;
    method tx   = i_tx;
endmodule

endpackage
