package CmodUartBridges;

import AXI4_Stream :: *;
import AXIStreamConverters :: *;
import FIFOF :: *;
import GetPut :: *;
import UartAxiLiteMaster :: *;
import UartRx :: *;
import UartTx :: *;

`ifndef CMOD_UART_PRESCALER
`define CMOD_UART_PRESCALER 100
`endif

`ifndef CMOD_UART_IDLE_TIMEOUT_CYCLES
`define CMOD_UART_IDLE_TIMEOUT_CYCLES 102400
`endif

typedef Bit#(16) UartPrescaler;
typedef Bit#(32) TimeoutCycles;

typedef enum {
    RouteIdle,
    RouteCtrl,
    RouteData
} CmodUartMode deriving(Bits, Eq, FShow);

interface CmodUartAxisBridge;
    (* always_enabled *) (* prefix="uart" *)
    method Action rx(Bit#(1) value);
    (* always_ready *) (* result="uart_tx" *)
    method Bit#(1) tx();
    (* always_enabled *) method Action tx_enable((* port="tx_enable" *) Bool value);

    (* prefix="M_AXIS" *) interface AXI4_Stream_Wr_Fab#(8, 1) m_axis;
    (* prefix="S_AXIS" *) interface AXI4_Stream_Rd_Fab#(8, 1) s_axis;

    (* always_ready *) method Bool rx_busy;
    (* always_ready *) method Bool tx_busy;
endinterface

interface CmodUartModeSwitch;
    (* always_enabled *) (* prefix="uart" *)
    method Action rx(Bit#(1) value);
    (* always_ready *) (* result="uart_tx" *)
    method Bit#(1) tx();

    (* always_enabled *) method Action ctrl_tx((* port="ctrl_uart_tx" *) Bit#(1) value);
    (* always_ready *) method Bit#(1) ctrl_rx();

    (* always_enabled *) method Action data_tx((* port="data_uart_tx" *) Bit#(1) value);
    (* always_enabled *) method Action data_rx_busy((* port="data_rx_busy" *) Bool value);
    (* always_enabled *) method Action data_tx_busy((* port="data_tx_busy" *) Bool value);
    (* always_ready *) method Bit#(1) data_rx();

    (* always_ready *) method Bit#(2) mode();
endinterface

function UartPrescaler cmod_uart_prescaler();
    return `CMOD_UART_PRESCALER;
endfunction

function TimeoutCycles cmod_uart_idle_timeout_cycles();
    return `CMOD_UART_IDLE_TIMEOUT_CYCLES;
endfunction

function AXI4_Stream_Pkg#(8, 1) uart_byte_to_axis(Bit#(8) data);
    return AXI4_Stream_Pkg {
        data: data,
        user: 0,
        keep: '1,
        dest: 0,
        id:   0,
        last: True
    };
endfunction

(* synthesize, default_clock_osc="aclk", default_reset="aresetn", clock_prefix="" *)
module mkCmodUartAxisBridge(CmodUartAxisBridge);
    UartRx#(8) uart_rx <- mkUartRxBuffered(1, cmod_uart_prescaler(), 32);
    UartTx#(8) uart_tx <- mkUartTxBuffered(1, cmod_uart_prescaler(), 64);
    AXI4_Stream_Wr#(8, 1) axis_out <- mkAXI4_Stream_Wr(32);
    AXI4_Stream_Rd#(8, 1) axis_in <- mkAXI4_Stream_Rd(64);
    Wire#(Bool) w_tx_enable <- mkDWire(False);

    rule rrx_to_axis;
        let data <- uart_rx.receive.get();
        axis_out.pkg.put(uart_byte_to_axis(data));
    endrule

    rule raxis_to_tx if(w_tx_enable);
        let data <- axis_in.pkg.get();
        uart_tx.transmit.put(data.data);
    endrule

    method rx = uart_rx.rx;
    method tx = uart_tx.tx;
    method Action tx_enable(Bool value);
        w_tx_enable <= value;
    endmethod
    method rx_busy = uart_rx.busy;
    method tx_busy = uart_tx.busy;

    interface m_axis = axis_out.fab;
    interface s_axis = axis_in.fab;
endmodule

(* synthesize, default_clock_osc="aclk", default_reset="aresetn", clock_prefix="" *)
module mkCmodUartModeSwitch(CmodUartModeSwitch);
    UartRx#(8) route_rx <- mkUartRxBuffered(1, cmod_uart_prescaler(), 2);

    Reg#(CmodUartMode) rg_mode <- mkReg(RouteIdle);
    Reg#(TimeoutCycles) rg_idle_cycles <- mkReg(0);

    Wire#(Bit#(1)) w_uart_rx <- mkDWire(1);
    Wire#(Bit#(1)) w_ctrl_tx <- mkDWire(1);
    Wire#(Bit#(1)) w_data_tx <- mkDWire(1);
    Wire#(Bool) w_data_rx_busy <- mkDWire(False);
    Wire#(Bool) w_data_tx_busy <- mkDWire(False);

    Bool route_idle = rg_mode == RouteIdle;
    Bool route_ctrl = rg_mode == RouteCtrl;
    Bool route_data = rg_mode == RouteData;
    Bit#(1) selected_tx = route_ctrl ? w_ctrl_tx : (route_data ? w_data_tx : 1);
    Bool selected_busy = route_data && (w_data_rx_busy || w_data_tx_busy);

    rule rroute_byte if(route_idle);
        let octet <- route_rx.receive.get();
        if(octet == 8'h43) begin
            rg_mode <= RouteCtrl;
        end else if(octet == 8'h44) begin
            rg_mode <= RouteData;
        end
    endrule

    rule ridle_timeout if(!route_idle);
        if(w_uart_rx == 1 && selected_tx == 1 && !selected_busy) begin
            if(rg_idle_cycles >= cmod_uart_idle_timeout_cycles()) begin
                rg_mode <= RouteIdle;
                rg_idle_cycles <= 0;
            end else begin
                rg_idle_cycles <= rg_idle_cycles + 1;
            end
        end else begin
            rg_idle_cycles <= 0;
        end
    endrule

    method Action rx(Bit#(1) value);
        w_uart_rx <= value;
        route_rx.rx(route_idle ? value : 1);
    endmethod

    method Bit#(1) tx = selected_tx;

    method Action ctrl_tx(Bit#(1) value);
        w_ctrl_tx <= value;
    endmethod

    method Bit#(1) ctrl_rx = route_ctrl ? w_uart_rx : 1;

    method Action data_tx(Bit#(1) value);
        w_data_tx <= value;
    endmethod

    method Action data_rx_busy(Bool value);
        w_data_rx_busy <= value;
    endmethod

    method Action data_tx_busy(Bool value);
        w_data_tx_busy <= value;
    endmethod

    method Bit#(1) data_rx = route_data ? w_uart_rx : 1;
    method Bit#(2) mode = pack(rg_mode);
endmodule

(* synthesize, default_clock_osc="aclk", default_reset="aresetn", clock_prefix="" *)
module mkCmodAxis8ToAxis24Frame(AXIStreamUpConverter#(8, 24, 1));
    let converter <- mkAXIStreamUpConverter();
    return converter;
endmodule

(* synthesize, default_clock_osc="aclk", default_reset="aresetn", clock_prefix="" *)
module mkCmodUartAxiLiteMaster(UartAxiLiteMaster#(32, 32));
    let bridge <- mkUartAxiLiteMasterBuffered(1, cmod_uart_prescaler(), 4, 4, 32, 8);
    return bridge;
endmodule

endpackage
