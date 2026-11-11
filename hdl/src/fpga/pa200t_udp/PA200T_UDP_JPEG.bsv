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

(* always_enabled *)
interface PA200T_UDP_JPEG_ifc;
    (* prefix="" *) method Action tms((* port="TMS" *) Bit#(1) t);
    (* prefix="" *) method Action tdi((* port="TDI" *) Bit#(1) t);
    (* prefix="", result="TDO" *) method Bit#(1) tdo;
    (* result="LED" *) method Bit#(2) leds;
    (* result="mdio_phy_rstn" *) method Bit#(1) phy_rstn;
    (* result="mdio_mdc" *) method Bit#(1) mdc;
    (* prefix="mdio_mdio" *) interface Inout#(Bit#(1)) mdio;
    (* prefix="rgmii" *) interface PA200T_UDP_RGMII_ifc rgmii;
`ifndef UDP_USE_BRAM
    (* prefix="ddr3" *) interface UdpDdr3Pins_ifc ddr3;
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
    interface UdpDdr3Pins_ifc ddr3;
`endif
endinterface

module [AddrMapCtx_t#(32, Axi4LiteSlaveFab_ifc#(32, 32))] pa200t_udp_addr_map#(
    Axi4LiteSlaveFab_ifc#(32, 32) sys,
    Axi4LiteSlaveFab_ifc#(32, 32) mdio,
    Axi4LiteSlaveFab_ifc#(32, 32) eth,
    Axi4LiteSlaveFab_ifc#(32, 32) jpeg
)(Empty);
    addr_map_def("PA200T JPEG UDP AXI4-Lite");
    addr_map_target('h0000, 'h1000, "SYS", sys);
    addr_map_target('h1000, 'h1000, "MDIO", mdio);
    addr_map_target('h2000, 'h1000, "ETH", eth);
    addr_map_target('h4000, 'h2000, "JPEG", jpeg);
endmodule

(* no_default_clock *)
module [Module] mkPA200T_UDP_JPEG_Top#(Clock tck, Clock clk_p, Clock clk_n, Clock rgmii_rxc)(PA200T_UDP_JPEG_ifc);
    let p_tms <- mkUdpPadIn(tck);
    let p_tdi <- mkUdpPadIn(tck);
    let inst  <- wrap_diff_clk(mkPA200T_UDP_JPEG_Clocks(tck, rgmii_rxc, p_tms.value, p_tdi.value), clk_p, clk_n);
    method    tms      = p_tms.pad;
    method    tdi      = p_tdi.pad;
    method    tdo      = inst.tdo;
    method    leds     = inst.leds;
    method    phy_rstn = inst.phy_rstn;
    method    mdc      = inst.mdc;
    interface mdio     = inst.mdio;
    interface rgmii    = inst.rgmii;
`ifndef UDP_USE_BRAM
    interface ddr3 = inst.ddr3;
`endif
endmodule

module [Module] mkPA200T_UDP_JPEG_Clocks#(Clock tck, Clock rgmii_rxc, Bit#(1) tms_in, Bit#(1) tdi_in)(PA200T_UDP_JPEG_Core_ifc);
    let clk_200  <- exposeCurrentClock;
    let i_pll    <- mkPA200T_UDP_PLL(clk_200);
    let rst_jtag <- mkAsyncResetFromCR(2, tck);
`ifdef UDP_USE_BRAM
    let i_mem <- mkUdpPatternRam(clocked_by i_pll.clk_bram, reset_by i_pll.rst_bram);
    let inst  <- mkPA200T_UDP_JPEG(tck, rst_jtag, tms_in, tdi_in, rgmii_rxc, clk_200, i_pll.rst_200, i_pll.clk_125, i_pll.clk_125_90, i_pll.rst_125, True, i_mem.s_rd, i_mem.s_wr,
        clocked_by i_pll.clk_bram, reset_by i_pll.rst_bram);
`else
    let rst_board <- exposeCurrentReset;
    let i_mig     <- mkUdpMig(clk_200, rst_board);
    let inst      <- mkPA200T_UDP_JPEG(tck, rst_jtag, tms_in, tdi_in, rgmii_rxc, clk_200, i_pll.rst_200, i_pll.clk_125, i_pll.clk_125_90, i_pll.rst_125, i_mig.calibrated, i_mig.s_rd, i_mig.s_wr, i_mig.pins,
        clocked_by i_mig.ui_clk, reset_by i_mig.ui_reset_n);
`endif
    return inst;
endmodule

module mkUdpTapInputs#(Bit#(1) tms_in, Bit#(1) tdi_in, JTAGSystem_ifc#(PA200T_UDP_JTAG_ifc) tap)(Empty);
    (* fire_when_enabled, no_implicit_conditions *)
    rule r_inputs;
        tap.tms(tms_in);
        tap.tdi(tdi_in);
    endrule
endmodule

module [Module] mkPA200T_UDP_JPEG#(Clock tck, Reset rst_jtag, Bit#(1) tms_in, Bit#(1) tdi_in, Clock rgmii_rxc, Clock clk_200, Reset rst_200, Clock clk_125, Clock clk_125_90, Reset rst_125,
    Bool calibrated, AXI4_Slave_Rd_Fab#(30, 32, 4, 0) mem_rd, AXI4_Slave_Wr_Fab#(30, 32, 4, 0) mem_wr
`ifndef UDP_USE_BRAM
    , UdpDdr3Pins_ifc ddr3_pins
`endif
)(PA200T_UDP_JPEG_Core_ifc);
    let clk    <- exposeCurrentClock;
    let rst    <- exposeCurrentReset;
    let i_jtag <- mkPA200T_UDP_JTAG_NATIVE(clk, rst, clocked_by tck, reset_by rst_jtag);
    mkUdpTapInputs(tms_in, tdi_in, i_jtag, clocked_by tck, reset_by rst_jtag);
    let i_sys  <- mkJpegUdpSystem(calibrated);
    let i_eth  <- mkPA200T_UDP_ETH(clk_125, clk_125_90, rst_125, rgmii_rxc, clk_200, rst_200);
    let i_mdio <- mkPA200T_UDP_MDIO;
    mkConnection(i_sys.m_mem_rd, mem_rd);
    mkConnection(i_sys.m_mem_wr, mem_wr);
    mkConnection(i_sys.tx_header, i_eth.tx_header);
    mkConnection(i_sys.tx_payload, i_eth.tx_payload);
    mkConnection(i_eth.rx_header, i_sys.rx_header);
    mkConnection(i_eth.rx_payload, i_sys.rx_payload);

    Axi4LiteBusCfg_t cfg_bus = defaultValue;
    cfg_bus.upstream_cut = axi4_lite_slice_request;
    cfg_bus.local_addr   = True;
    AddrMapCollected_t#(4, Axi4LiteSlaveFab_ifc#(32, 32), Empty) map <- collect_addr_map(pa200t_udp_addr_map(
        axi4_lite_slave_fab(i_sys.s_sys_rd, i_sys.s_sys_wr),
        axi4_lite_slave_fab(i_mdio.s_rd, i_mdio.s_wr),
        axi4_lite_slave_fab(i_eth.s_rd, i_eth.s_wr),
        axi4_lite_slave_fab(i_sys.s_jpeg_rd, i_sys.s_jpeg_wr)));
    messageM(doc_addr_map(map).text);
    AddrMapBus_ifc#(4, Axi4LiteSlaveFab_ifc#(32, 32), Empty) i_bus <- mkAddrMapBus(cfg_bus, map);
    mkConnection(axi4_lite_master_fab(i_jtag.device_ifc.m_axil_rd, i_jtag.device_ifc.m_axil_wr), i_bus.up);
    ReadOnly#(Bit#(2)) p_leds <- mkNullCrossingWire(noClock, {pack(calibrated), pack(i_sys.irq)});
    ReadOnly#(Bit#(1)) p_rst  <- mkNullCrossingWire(noClock, pack(i_mdio.phy_rstn));
    ReadOnly#(Bit#(1)) p_mdc  <- mkNullCrossingWire(noClock, i_mdio.mdc);
    method    tdo      = i_jtag.tdo;
    method    leds     = p_leds;
    method    phy_rstn = p_rst;
    method    mdc      = p_mdc;
    interface mdio     = i_mdio.mdio;
    interface rgmii    = i_eth.rgmii;
`ifndef UDP_USE_BRAM
    interface ddr3 = ddr3_pins;
`endif
endmodule

endpackage
