package PA200T_UDP_JPEG;

import Clocks :: *;
import Connectable :: *;
import DefaultValue :: *;
import Axi4Lite :: *;
import Axi4LiteAddrMap :: *;
import Axi4LiteRegSlice :: *;
import BlueAddrMap :: *;
import BlueJ :: *;
import BlueXLNX :: *;
import AXI4_Slave :: *;

import JpegUdpSystem :: *;
import PA200T_UDP_ETH :: *;
import PA200T_UDP_JTAG :: *;
import PA200T_UDP_PLL :: *;
import UdpPatternRam :: *;
import UdpMig :: *;
import UdpBoardPins :: *;
import UdpMemoryCdc :: *;

(* always_enabled *)
interface PA200T_UDP_JPEG_ifc;
    (* prefix = "" *)
    method Action tms((* port = "TMS" *) Bit#(1) t);
    (* prefix = "" *)
    method Action tdi((* port = "TDI" *) Bit#(1) t);
    (* prefix = "", result = "TDO" *)
    method Bit#(1) tdo;
    (* result = "LED" *)
    method Bit#(2) leds;
    (* result = "mdio_phy_rstn" *)
    method Bit#(1) phy_rstn;
    (* result = "mdio_mdc" *)
    method Bit#(1) mdc;
    (* prefix = "mdio_mdio" *)
    interface Inout#(Bit#(1)) mdio;
    (* prefix = "rgmii" *)
    interface PA200T_UDP_RGMII_ifc rgmii;
`ifndef UDP_USE_BRAM
    (* prefix = "ddr3" *)
    interface UdpDdr3Pins_ifc ddr3;
`endif
endinterface

interface PA200T_UDP_JPEG_Core_ifc;
    method Bit#(1)                 tdo;
    method Bit#(2)                 leds;
    method Bit#(1)                 phy_rstn;
    method Bit#(1)                 mdc;
    interface Inout#(Bit#(1))      mdio;
    interface PA200T_UDP_RGMII_ifc rgmii;
`ifndef UDP_USE_BRAM
    interface UdpDdr3Pins_ifc      ddr3;
`endif
endinterface

module [AddrMapCtx_t#(32, Axi4LiteSlaveFab_ifc#(32, 32))] pa200t_udp_addr_map#(Axi4LiteSlaveFab_ifc#(32, 32) sys, Axi4LiteSlaveFab_ifc#(32, 32) mdio, Axi4LiteSlaveFab_ifc#(32, 32) eth, Axi4LiteSlaveFab_ifc#(32, 32) jpeg)(Empty);
    addr_map_def("PA200T JPEG UDP AXI4-Lite");
    addr_map_target('h0000, 'h1000, "SYS",  sys);
    addr_map_target('h1000, 'h1000, "MDIO", mdio);
    addr_map_target('h2000, 'h1000, "ETH",  eth);
    addr_map_target('h4000, 'h2000, "JPEG", jpeg);
endmodule

(* no_default_clock *)
module [Module] mkPA200T_UDP_JPEG_Top#(Clock tck, Clock clk_p, Clock clk_n, Clock rgmii_rxc)(PA200T_UDP_JPEG_ifc);
    UdpPadIn_ifc             i_tms  <- mkUdpPadIn(tck);
    UdpPadIn_ifc             i_tdi  <- mkUdpPadIn(tck);
    PA200T_UDP_JPEG_Core_ifc i_core <- wrap_diff_clk(mkPA200T_UDP_JPEG_Clocks(tck, rgmii_rxc, i_tms.value, i_tdi.value), clk_p, clk_n);

    method tms      = i_tms.pad;
    method tdi      = i_tdi.pad;
    method tdo      = i_core.tdo;
    method leds     = i_core.leds;
    method phy_rstn = i_core.phy_rstn;
    method mdc      = i_core.mdc;
    interface mdio  = i_core.mdio;
    interface rgmii = i_core.rgmii;
`ifndef UDP_USE_BRAM
    interface ddr3  = i_core.ddr3;
`endif
endmodule

/*
 * Clocks, resets and the frame memory around the board logic:
 *   UDP_USE_BRAM   BRAM pattern store, everything on the 83.333 MHz BRAM test clock
 *   UDP_DEMO_200   DDR3 behind a clock crossing, system at 125 MHz, encoder and DCT on their own PLL clocks
 *   default        DDR3, everything on the MIG user interface clock
 */
module [Module] mkPA200T_UDP_JPEG_Clocks#(Clock tck, Clock rgmii_rxc, Bit#(1) tms_in, Bit#(1) tdi_in)(PA200T_UDP_JPEG_Core_ifc);
    Clock              clk_200  <- exposeCurrentClock;
    PA200T_UDP_PLL_ifc i_pll    <- mkPA200T_UDP_PLL(clk_200);
    Reset              rst_jtag <- mkAsyncResetFromCR(2, tck);

`ifdef UDP_USE_BRAM
    UdpPatternRam_ifc        i_mem  <- mkUdpPatternRam(clocked_by i_pll.clk_bram, reset_by i_pll.rst_bram);
    PA200T_UDP_JPEG_Core_ifc i_core <- mkPA200T_UDP_JPEG(tck, rst_jtag, tms_in, tdi_in, rgmii_rxc, clk_200, i_pll.rst_200, i_pll.clk_125, i_pll.clk_125_90, i_pll.rst_125, True, i_mem.s_rd, i_mem.s_wr, clocked_by i_pll.clk_bram, reset_by i_pll.rst_bram);
`else
    Reset rst_board <- exposeCurrentReset;
`ifdef UDP_DEMO_200
    UdpMig_ifc           i_mig         <- mkUdpMig(clk_200, i_pll.rst_200);
    //reset every transaction domain from the same source, including MIG on PLL loss
    Reset                rst_mig_ref   <- mkAsyncReset(2, i_mig.ui_reset_n, clk_200);
    Reset                rst_source    <- mkResetEither(i_pll.rst_200, rst_mig_ref);
    Reset                rst_system    <- mkAsyncReset(4, rst_source, i_pll.clk_125);
    Reset                rst_encoder   <- mkAsyncReset(4, rst_source, i_pll.clk_app);
    Reset                rst_dct       <- mkAsyncReset(2, rst_source, i_pll.clk_dct);
    Reset                rst_memory    <- mkAsyncReset(2, rst_source, i_mig.ui_clk);
    Reset                rst_jtag_demo <- mkAsyncReset(2, rst_source, tck);
    UdpMemoryCdc_ifc     i_cdc         <- mkUdpMemoryCdc(i_mig.ui_clk, rst_memory, clocked_by i_pll.clk_125, reset_by rst_system);
    SyncBitIfc#(Bit#(1)) i_calibrated  <- mkSyncBit(i_mig.ui_clk, i_mig.ui_reset_n, i_pll.clk_125);

    mkConnection(i_cdc.m_rd, i_mig.s_rd);
    mkConnection(i_cdc.m_wr, i_mig.s_wr);

    rule r_calibrated;
        i_calibrated.send(pack(i_mig.calibrated));
    endrule

    PA200T_UDP_JPEG_Core_ifc i_core <- mkPA200T_UDP_JPEG(tck, rst_jtag_demo, tms_in, tdi_in, rgmii_rxc, clk_200, i_pll.rst_200, i_pll.clk_125, i_pll.clk_125_90, rst_system, i_pll.clk_app, rst_encoder, i_pll.clk_dct, rst_dct, i_calibrated.read == 1, i_cdc.s_rd, i_cdc.s_wr, i_mig.pins, clocked_by i_pll.clk_125, reset_by rst_system);
`else
    UdpMig_ifc               i_mig  <- mkUdpMig(clk_200, rst_board);
    PA200T_UDP_JPEG_Core_ifc i_core <- mkPA200T_UDP_JPEG(tck, rst_jtag, tms_in, tdi_in, rgmii_rxc, clk_200, i_pll.rst_200, i_pll.clk_125, i_pll.clk_125_90, i_pll.rst_125, i_mig.calibrated, i_mig.s_rd, i_mig.s_wr, i_mig.pins, clocked_by i_mig.ui_clk, reset_by i_mig.ui_reset_n);
`endif
`endif
    return i_core;
endmodule

module mkUdpTapInputs#(Bit#(1) tms_in, Bit#(1) tdi_in, JTAGSystem_ifc#(PA200T_UDP_JTAG_ifc) tap)(Empty);
    (* fire_when_enabled, no_implicit_conditions *)
    rule r_inputs;
        tap.tms(tms_in);
        tap.tdi(tdi_in);
    endrule
endmodule

module [Module] mkPA200T_UDP_JPEG#(Clock tck, Reset rst_jtag, Bit#(1) tms_in, Bit#(1) tdi_in, Clock rgmii_rxc, Clock clk_200, Reset rst_200, Clock clk_125, Clock clk_125_90, Reset rst_125,
`ifdef UDP_DEMO_200
    Clock clk_enc, Reset rst_enc, Clock clk_dct, Reset rst_dct,
`endif
    Bool calibrated, AXI4_Slave_Rd_Fab#(30, 32, 4, 0) mem_rd, AXI4_Slave_Wr_Fab#(30, 32, 4, 0) mem_wr
`ifndef UDP_USE_BRAM
    , UdpDdr3Pins_ifc ddr3_pins
`endif
)(PA200T_UDP_JPEG_Core_ifc);
    Clock                                clk_sys <- exposeCurrentClock;
    Reset                                rst_sys <- exposeCurrentReset;
    JTAGSystem_ifc#(PA200T_UDP_JTAG_ifc) i_jtag  <- mkPA200T_UDP_JTAG_NATIVE(clk_sys, rst_sys, clocked_by tck, reset_by rst_jtag);
`ifdef UDP_DEMO_200
    JpegUdpSystem_ifc                    i_sys   <- mkJpegUdpSystemAsync(calibrated, clk_enc, rst_enc, clk_dct, rst_dct);
`else
    JpegUdpSystem_ifc                    i_sys   <- mkJpegUdpSystem(calibrated);
`endif
    PA200T_UDP_ETH_ifc                   i_eth   <- mkPA200T_UDP_ETH(clk_125, clk_125_90, rst_125, rgmii_rxc, clk_200, rst_200);
    PA200T_UDP_MDIO_ifc                  i_mdio  <- mkPA200T_UDP_MDIO;

    mkUdpTapInputs(tms_in, tdi_in, i_jtag, clocked_by tck, reset_by rst_jtag);

    mkConnection(i_sys.m_mem_rd,   mem_rd);
    mkConnection(i_sys.m_mem_wr,   mem_wr);
    mkConnection(i_sys.tx_header,  i_eth.tx_header);
    mkConnection(i_sys.tx_payload, i_eth.tx_payload);
    mkConnection(i_eth.rx_header,  i_sys.rx_header);
    mkConnection(i_eth.rx_payload, i_sys.rx_payload);

    //JTAG-to-AXI master -> address-decoded register bus
    Axi4LiteBusCfg_t cfg_bus = defaultValue;
    cfg_bus.upstream_cut = axi4_lite_slice_request;
    cfg_bus.local_addr   = True;

    AddrMapCollected_t#(4, Axi4LiteSlaveFab_ifc#(32, 32), Empty) addr_map <- collect_addr_map(pa200t_udp_addr_map(axi4_lite_slave_fab(i_sys.s_sys_rd, i_sys.s_sys_wr), axi4_lite_slave_fab(i_mdio.s_rd, i_mdio.s_wr), axi4_lite_slave_fab(i_eth.s_rd, i_eth.s_wr), axi4_lite_slave_fab(i_sys.s_jpeg_rd, i_sys.s_jpeg_wr)));
    AddrMapBus_ifc#(4, Axi4LiteSlaveFab_ifc#(32, 32), Empty)     i_bus    <- mkAddrMapBus(cfg_bus, addr_map);

    messageM(doc_addr_map(addr_map).text);
    mkConnection(axi4_lite_master_fab(i_jtag.device_ifc.m_axil_rd, i_jtag.device_ifc.m_axil_wr), i_bus.up);

    //output pins are asynchronous to the board anyway
    ReadOnly#(Bit#(2)) i_leds     <- mkNullCrossingWire(noClock, {pack(calibrated), pack(i_sys.irq)});
    ReadOnly#(Bit#(1)) i_phy_rstn <- mkNullCrossingWire(noClock, pack(i_mdio.phy_rstn));
    ReadOnly#(Bit#(1)) i_mdc      <- mkNullCrossingWire(noClock, i_mdio.mdc);

    method tdo      = i_jtag.tdo;
    method leds     = i_leds;
    method phy_rstn = i_phy_rstn;
    method mdc      = i_mdc;
    interface mdio  = i_mdio.mdio;
    interface rgmii = i_eth.rgmii;
`ifndef UDP_USE_BRAM
    interface ddr3  = ddr3_pins;
`endif
endmodule

endpackage
