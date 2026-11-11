package UdpBoardPins;

import Clocks :: *;

(* always_ready, always_enabled *)
interface UdpPadIn_ifc;
    method Action  pad(Bit#(1) value);
    method Bit#(1) value;
endinterface

//the pad has no reset, its value is sampled by logic in the supplied clock domain
import "BVI" IBUF =
module mkUdpPadIn#(Clock pad_clk)(UdpPadIn_ifc);
    default_clock no_clock;
    default_reset no_reset;
    input_clock pad_clk() = pad_clk;
    method pad(I) enable((* inhigh *) EN_PAD) clocked_by(pad_clk) reset_by(no_reset);
    method O value clocked_by(no_clock) reset_by(no_reset);
    path(I, O);
    schedule pad C pad;
    schedule value CF value;
endmodule

endpackage
