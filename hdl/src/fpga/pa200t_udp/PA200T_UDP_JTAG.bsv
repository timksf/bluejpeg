package PA200T_UDP_JTAG;

//copied from pa200t/hdl/src/PA200T_UDP_JTAG.bsv, keep the TAP identical so the pa200t host scripts apply

import Clocks :: *;
import BlueJ :: *;
import BlueAXI :: *;
import JTAG2AXI :: *;

typedef struct {
    Bit#(w) blink_div;
    Bit#(n) blink_en;
} JtagLedCtrl_t#(numeric type n, numeric type w) deriving(Bits, Eq, FShow);

interface LEDControl_ifc#(numeric type n);
    method Bit#(n) pins;
endinterface

interface PA200T_UDP_JTAG_ifc;
    interface Bit#(2) leds;

    interface AXI4_Lite_Master_Rd_Fab#(32, 32) m_axil_rd;
    interface AXI4_Lite_Master_Wr_Fab#(32, 32) m_axil_wr;
endinterface

module mkLEDControl#(Reg#(JtagLedCtrl_t#(n, w)) rg_led_ctrl)(LEDControl_ifc#(n));
    Reg#(Bit#(w)) rg_div  <- mkReg(0);
    Reg#(Bit#(n)) rg_leds <- mkReg(0);

    rule r_div;
        if(rg_div < zeroExtend(rg_led_ctrl.blink_div)) rg_div <= rg_div + 1;
        else                                           rg_div <= 0;
    endrule

    //turn off disabled leds and toggle enabled leds
    rule r_toggle (rg_div == zeroExtend(rg_led_ctrl.blink_div));
        rg_leds <= (rg_leds ^ rg_led_ctrl.blink_en) & rg_led_ctrl.blink_en;
    endrule

    method pins = rg_leds;
endmodule

//the bscan variant needs no pins as those are mapped implicitly by vivado
module [Module] mkPA200T_UDP_JTAG_BSCANE2(PA200T_UDP_JTAG_ifc);
    BSCANE2_Config cfg_bscan_led = BSCANE2_Config { p_DISABLE_JTAG: False, p_JTAG_CHAIN: 3 };
    BSCANE2_Config cfg_bscan_axi = BSCANE2_Config { p_DISABLE_JTAG: False, p_JTAG_CHAIN: 4 };

    Clock       clk_sys  <- exposeCurrentClock;
    Reset       rst_sys  <- exposeCurrentReset;
    BSCANE2_ifc i_bscan3 <- mkBSCANE2(cfg_bscan_led);
    BSCANE2_ifc i_bscan4 <- mkBSCANE2(cfg_bscan_axi);
    Clock       tck3     = i_bscan3.bscan_tck;
    Reset       rst_tck3 <- mkAsyncResetFromCR(2, tck3);
    Clock       tck4     = i_bscan4.bscan_tck;
    Reset       rst_tck4 <- mkAsyncResetFromCR(2, tck4);  //keep the jtag subsystem in reset for 2 tck cycles

    JTAG2AXIL_ifc#(32, 32)               i_jtag2axil <- mkJTAG2AXI(clk_sys, rst_sys, clocked_by tck4, reset_by rst_tck4);
    Reg#(JtagLedCtrl_t#(2, 32))          rg_led_ctrl <- mkRegU;
    JTAG_Reg_ifc#(JtagLedCtrl_t#(2, 32)) i_led_ctrl  <- mkJTAG_Reg_Sync(unpack('hdeadbeef), clk_sys, rst_sys, clocked_by tck3, reset_by rst_tck3);
    LEDControl_ifc#(2)                   i_leds      <- mkLEDControl(rg_led_ctrl);

    connect_bscane2_to_target(i_bscan3, i_led_ctrl.scan);
    connect_bscane2_to_target(i_bscan4, i_jtag2axil.scan);

    rule r_upd_ctrl (i_led_ctrl.wr_o);
        rg_led_ctrl <= i_led_ctrl.reg_o;
        $display("Updating control to: ", fshow(i_led_ctrl.reg_o));
    endrule

    method leds = i_leds.pins;

    interface m_axil_rd = i_jtag2axil.m_axil_rd;
    interface m_axil_wr = i_jtag2axil.m_axil_wr;
endmodule

//custom tap variant; the jtag system itself runs in the TCK domain, everything that leaves this domain has to use CDC
module [JTAGSystem#(2, 3)] pa200t_udp_jtag_system#(Clock clk_sys, Reset rst_sys)(PA200T_UDP_JTAG_ifc);
    jtag_meta_config(0, 'b00000010111, 'h04);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(0);
    jtag_rst_to_idcode();

    //jtag data registers and led control
    JTAG2AXIL_ifc#(32, 32)      i_jtag2axil <- mkJTAG2AXI(clk_sys, rst_sys);
    Reg#(JtagLedCtrl_t#(2, 32)) rg_led_ctrl <- mkReg(unpack(0), clocked_by clk_sys, reset_by rst_sys);
    LEDControl_ifc#(2)          i_leds      <- mkLEDControl(rg_led_ctrl, clocked_by clk_sys, reset_by rst_sys);

    //jtag system definition
    jtag_scan_endpoint(i_jtag2axil.scan, 'h03);
    jtag_sync_reg_io(unpack('hdeadbeef), rg_led_ctrl, 'h04, clk_sys, rst_sys);

    method leds = i_leds.pins;

    interface m_axil_rd = i_jtag2axil.m_axil_rd;
    interface m_axil_wr = i_jtag2axil.m_axil_wr;
endmodule

module [Module] mkPA200T_UDP_JTAG_NATIVE#(Clock clk_sys, Reset rst_sys)(JTAGSystem_ifc#(PA200T_UDP_JTAG_ifc));
    JTAGSystem_ifc#(PA200T_UDP_JTAG_ifc) i_jtag_sys <- build_jtag_system(pa200t_udp_jtag_system(clk_sys, rst_sys));
    return i_jtag_sys;
endmodule

endpackage
