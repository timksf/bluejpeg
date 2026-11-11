package UdpMig;

import Clocks :: *;

import AXI4_Slave :: *;
import AXI4_Types :: *;

(* always_ready, always_enabled *)
interface UdpDdr3Pins_ifc;
    interface Inout#(Bit#(32)) dq;
    interface Inout#(Bit#(4))  dqs_p;
    interface Inout#(Bit#(4))  dqs_n;
    method Bit#(15)            addr;
    method Bit#(3)             ba;
    method Bit#(1)             ras_n;
    method Bit#(1)             cas_n;
    method Bit#(1)             we_n;
    method Bit#(1)             reset_n;
    method Bit#(1)             ck_p;
    method Bit#(1)             ck_n;
    method Bit#(1)             cke;
    method Bit#(1)             cs_n;
    method Bit#(4)             dm;
    method Bit#(1)             odt;
endinterface

interface UdpMig_ifc;
    interface Clock                            ui_clk;
    interface Reset                            ui_reset_n;
    interface UdpDdr3Pins_ifc                  pins;
    interface AXI4_Slave_Rd_Fab#(30, 32, 4, 0) s_rd;
    interface AXI4_Slave_Wr_Fab#(30, 32, 4, 0) s_wr;
    method Bool                                calibrated;
endinterface

(* always_ready, always_enabled *)
interface UdpMigRaw_ifc;
    interface Clock           ui_clk;
    interface Reset           ui_reset_n;
    interface UdpDdr3Pins_ifc pins;
    method Action             ar(Bit#(4) id, Bit#(30) addr, UInt#(8) len, AXI4_BurstSize size, AXI4_BurstType burst, AXI4_Lock lock, AXI4_Read_Cache cache, AXI4_Prot prot, Bit#(4) qos);
    method Action             arvalid(Bool value);
    method Bool               arready;
    method Action             aw(Bit#(4) id, Bit#(30) addr, UInt#(8) len, AXI4_BurstSize size, AXI4_BurstType burst, AXI4_Lock lock, AXI4_Write_Cache cache, AXI4_Prot prot, Bit#(4) qos);
    method Action             awvalid(Bool value);
    method Bool               awready;
    method Action             write_data(Bit#(32) data, Bit#(4) strb, Bool last);
    method Action             wvalid(Bool value);
    method Action             bready(Bool value);
    method Action             rready(Bool value);
    method Bool               wready;
    method Bool               bvalid;
    method Bit#(4)            bid;
    method AXI4_Response      bresp;
    method Bool               rvalid;
    method Bit#(4)            rid;
    method Bit#(32)           rdata;
    method AXI4_Response      rresp;
    method Bool               rlast;
    method Bool               calibrated;
endinterface

import "BVI" udp_mig_wrapper =
module mkUdpMigRaw#(Clock sys_clk, Reset sys_reset_n)(UdpMigRaw_ifc);
    default_clock no_clock;
    default_reset no_reset;
    input_clock sys_clk(sys_clk_i) = sys_clk;
    input_reset sys_reset_n(sys_rst_n) clocked_by(sys_clk) = sys_reset_n;
    output_clock ui_clk(ui_clk);
    output_reset ui_reset_n(ui_reset_n) clocked_by(ui_clk);
    interface UdpDdr3Pins_ifc pins;
        ifc_inout dq   (ddr3_dq)    clocked_by(no_clock) reset_by(no_reset);
        ifc_inout dqs_p(ddr3_dqs_p) clocked_by(no_clock) reset_by(no_reset);
        ifc_inout dqs_n(ddr3_dqs_n) clocked_by(no_clock) reset_by(no_reset);
        method ddr3_addr    addr    clocked_by(no_clock) reset_by(no_reset);
        method ddr3_ba      ba      clocked_by(no_clock) reset_by(no_reset);
        method ddr3_ras_n   ras_n   clocked_by(no_clock) reset_by(no_reset);
        method ddr3_cas_n   cas_n   clocked_by(no_clock) reset_by(no_reset);
        method ddr3_we_n    we_n    clocked_by(no_clock) reset_by(no_reset);
        method ddr3_reset_n reset_n clocked_by(no_clock) reset_by(no_reset);
        method ddr3_ck_p    ck_p    clocked_by(no_clock) reset_by(no_reset);
        method ddr3_ck_n    ck_n    clocked_by(no_clock) reset_by(no_reset);
        method ddr3_cke     cke     clocked_by(no_clock) reset_by(no_reset);
        method ddr3_cs_n    cs_n    clocked_by(no_clock) reset_by(no_reset);
        method ddr3_dm      dm      clocked_by(no_clock) reset_by(no_reset);
        method ddr3_odt     odt     clocked_by(no_clock) reset_by(no_reset);
    endinterface
    method ar(s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst, s_axi_arlock, s_axi_arcache, s_axi_arprot, s_axi_arqos) enable((* inhigh *) EN_ar) clocked_by(ui_clk) reset_by(ui_reset_n);
    method arvalid(s_axi_arvalid) enable((* inhigh *) EN_arvalid) clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_arready arready clocked_by(ui_clk) reset_by(ui_reset_n);
    method aw(s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst, s_axi_awlock, s_axi_awcache, s_axi_awprot, s_axi_awqos) enable((* inhigh *) EN_aw) clocked_by(ui_clk) reset_by(ui_reset_n);
    method awvalid(s_axi_awvalid) enable((* inhigh *) EN_awvalid) clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_awready awready clocked_by(ui_clk) reset_by(ui_reset_n);
    method write_data(s_axi_wdata, s_axi_wstrb, s_axi_wlast) enable((* inhigh *) EN_write_data) clocked_by(ui_clk) reset_by(ui_reset_n);
    method wvalid(s_axi_wvalid) enable((* inhigh *) EN_wvalid) clocked_by(ui_clk) reset_by(ui_reset_n);
    method bready(s_axi_bready) enable((* inhigh *) EN_bready) clocked_by(ui_clk) reset_by(ui_reset_n);
    method rready(s_axi_rready) enable((* inhigh *) EN_rready) clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_wready wready clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_bvalid bvalid clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_bid bid clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_bresp bresp clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_rvalid rvalid clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_rid rid clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_rdata rdata clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_rresp rresp clocked_by(ui_clk) reset_by(ui_reset_n);
    method s_axi_rlast rlast clocked_by(ui_clk) reset_by(ui_reset_n);
    method init_calib_complete calibrated clocked_by(ui_clk) reset_by(ui_reset_n);
    schedule (arready, awready, wready, bvalid, bid, bresp, rvalid, rid, rdata, rresp, rlast, calibrated, pins.addr, pins.ba, pins.ras_n, pins.cas_n, pins.we_n, pins.reset_n, pins.ck_p, pins.ck_n, pins.cke, pins.cs_n, pins.dm, pins.odt) CF (arready, awready, wready, bvalid, bid, bresp, rvalid, rid, rdata, rresp, rlast, calibrated, pins.addr, pins.ba, pins.ras_n, pins.cas_n, pins.we_n, pins.reset_n, pins.ck_p, pins.ck_n, pins.cke, pins.cs_n, pins.dm, pins.odt, ar, arvalid, aw, awvalid, write_data, wvalid, bready, rready);
    schedule ar C ar;
    schedule ar CF (arvalid, aw, awvalid, write_data, wvalid, bready, rready);
    schedule arvalid C arvalid;
    schedule arvalid CF (aw, awvalid, write_data, wvalid, bready, rready);
    schedule aw C aw;
    schedule aw CF (awvalid, write_data, wvalid, bready, rready);
    schedule awvalid C awvalid;
    schedule awvalid CF (write_data, wvalid, bready, rready);
    schedule write_data C write_data;
    schedule write_data CF (wvalid, bready, rready);
    schedule wvalid C wvalid;
    schedule wvalid CF (bready, rready);
    schedule bready C bready;
    schedule bready CF (rready);
    schedule rready C rready;
endmodule

(* no_default_clock *)
module mkUdpMig#(Clock sys_clk, Reset sys_reset_n)(UdpMig_ifc);
    let i_mig <- mkUdpMigRaw(sys_clk, sys_reset_n);
    interface ui_clk     = i_mig.ui_clk;
    interface ui_reset_n = i_mig.ui_reset_n;
    interface pins       = i_mig.pins;
    method    calibrated = i_mig.calibrated;
    interface AXI4_Slave_Rd_Fab s_rd;
        method parvalid = i_mig.arvalid;
        method arready  = i_mig.arready;
        method prready  = i_mig.rready;
        method rvalid   = i_mig.rvalid;
        method rid      = i_mig.rid;
        method rdata    = i_mig.rdata;
        method rresp    = i_mig.rresp;
        method rlast    = i_mig.rlast;
        method ruser    = 0;
        method Action parchannel(Bit#(4) id, Bit#(30) addr, UInt#(8) len, AXI4_BurstSize size, AXI4_BurstType burst, AXI4_Lock lock, AXI4_Read_Cache cache, AXI4_Prot prot, Bit#(4) qos, Bit#(4) region, Bit#(0) user);
            i_mig.ar(id, addr, len, size, burst, lock, cache, prot, qos);
        endmethod
    endinterface
    interface AXI4_Slave_Wr_Fab s_wr;
        method pawvalid = i_mig.awvalid;
        method awready  = i_mig.awready;
        method pwvalid  = i_mig.wvalid;
        method wready   = i_mig.wready;
        method pbready  = i_mig.bready;
        method bvalid   = i_mig.bvalid;
        method bid      = i_mig.bid;
        method bresp    = i_mig.bresp;
        method buser    = 0;
        method Action pawchannel(Bit#(4) id, Bit#(30) addr, UInt#(8) len, AXI4_BurstSize size, AXI4_BurstType burst, AXI4_Lock lock, AXI4_Write_Cache cache, AXI4_Prot prot, Bit#(4) qos, Bit#(4) region, Bit#(0) user);
            i_mig.aw(id, addr, len, size, burst, lock, cache, prot, qos);
        endmethod
        method Action pwchannel(Bit#(32) data, Bit#(4) strb, Bool last, Bit#(0) user);
            i_mig.write_data(data, strb, last);
        endmethod
    endinterface
endmodule

endpackage
