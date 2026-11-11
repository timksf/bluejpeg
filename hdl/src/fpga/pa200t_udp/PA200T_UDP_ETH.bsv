package PA200T_UDP_ETH;

import Clocks :: *;
import Connectable :: *;
import DefaultValue :: *;
import GetPut :: *;

import AXI4_Lite_Slave :: *;
import BlueXLNX :: *;
import Ethernet :: *;

(* always_ready, always_enabled *)
interface PA200T_UDP_MDIO_ifc;
    method Bool                               phy_rstn;
    method Bit#(1)                            mdc;
    interface Inout#(Bit#(1))                 mdio;
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_wr;
endinterface

module [Module] mkPA200T_UDP_MDIO(PA200T_UDP_MDIO_ifc);
    MdioAxiLite_ifc i_mdio <- mkMdioAxiLite;
    IOBUF_ifc       i_io   <- mkIOBUF(defaultValue);
    mkConnection(i_io.i, i_mdio.pins.mdio_i);
    mkConnection(i_mdio.pins.mdio_o, i_io.o);
    rule r_mdio_oe;
        i_io.oe(pack(i_mdio.pins.mdio_oe));
    endrule
    method    phy_rstn = i_mdio.phy_reset_n;
    method    mdc      = i_mdio.pins.mdc;
    interface mdio     = i_io.io;
    interface s_rd     = i_mdio.s_rd;
    interface s_wr     = i_mdio.s_wr;
endmodule

(* always_ready, always_enabled *)
interface PA200T_UDP_RGMII_ifc;
    method Bit#(1) txc;
    method Bit#(4) txd;
    method Bit#(1) tx_ctl;
    (* prefix="" *) method Action rx((* port="rxd" *) Bit#(4) rxd, (* port="rx_ctl" *) Bit#(1) rx_ctl);
endinterface

interface PA200T_UDP_ETH_ifc;
    interface PA200T_UDP_RGMII_ifc            rgmii;
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_wr;
    interface Put#(UdpTxRequest)              tx_header;
    interface EthernetStreamSink_ifc          tx_payload;
    interface Get#(UdpRxHeader)               rx_header;
    interface EthernetStreamSource_ifc        rx_payload;
endinterface

module [Module] mkPA200T_UDP_ETH#(Clock clk_125, Clock clk_125_90, Reset rst_125, Clock rgmii_rxc, Clock clk_200, Reset rst_200)(PA200T_UDP_ETH_ifc);
    UdpParameters cfg_udp = defaultValue;
    cfg_udp.checksum_payload_fifo_depth = 2048;
    cfg_udp.arp_request_retry_interval  = 162500000;
    cfg_udp.arp_request_timeout         = 2437500000;
    RgmiiMacParameters      cfg_mac    = defaultValue;
    let                     i_eth      <- mkUdpRgmiiAxiLite(cfg_udp, cfg_mac, clk_125, clk_125_90, rst_125, rgmii_rxc);
    IDELAYE2s_Fixed_ifc#(5) i_rx_delay <- mkIDELAYE2s_Fixed(idelaye2_fixed(11), clocked_by rgmii_rxc, reset_by noReset);
    IDELAYCTRL_ifc          i_dly_ctrl <- mkIDELAYCTRL(clocked_by clk_200, reset_by rst_200);
    ReadOnly#(Bit#(1))      w_txc      <- mkClockValue(i_eth.pins.tx_clk);
    rule r_unused_mdio;
        i_eth.mdio.mdio_i(1);
    endrule
    interface PA200T_UDP_RGMII_ifc rgmii;
        method txc    = w_txc;
        method txd    = i_eth.pins.tx_data;
        method tx_ctl = i_eth.pins.tx_ctl;
        method Action rx(Bit#(4) rxd, Bit#(1) rx_ctl);
            i_rx_delay.i({rx_ctl, rxd});
            let data = i_rx_delay.o;
            i_eth.pins.rx_data(data[3:0], data[4]);
        endmethod
    endinterface
    interface s_rd       = i_eth.s_rd;
    interface s_wr       = i_eth.s_wr;
    interface tx_header  = i_eth.tx_header;
    interface tx_payload = i_eth.tx_payload;
    interface rx_header  = i_eth.rx_header;
    interface rx_payload = i_eth.rx_payload;
endmodule

endpackage
