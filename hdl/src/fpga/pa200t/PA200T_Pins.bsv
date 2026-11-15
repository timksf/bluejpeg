package PA200T_Pins;

(* always_enabled *)
interface PadIn_ifc;
    //pad side, a method of the synthesized top
    method Action  pad(Bit#(1) b);
    //buffered value without clock and reset, the reader synchronizes it
    method Bit#(1) i;
endinterface

/*
 * Xilinx IBUF for an asynchronous input pin. An action method needs a clock to be enabled,
 * so pad is clocked by pad_clk, which has to be a clock of the synthesized top. That clock
 * only gives the method a domain and is not connected. The output has neither clock nor
 * reset, so it can feed any domain without tying it to the board reset.
 */
import "BVI" IBUF =
module mkPadIn#(Clock pad_clk)(PadIn_ifc);
    default_clock no_clock;
    default_reset no_reset;
    input_clock pad_clk() = pad_clk;

    method pad(I) enable((* inhigh *) EN_PAD) clocked_by(pad_clk) reset_by(no_reset);
    method O i() clocked_by(no_clock) reset_by(no_reset);

    path(I, O);
    schedule pad C pad;
    schedule i CF i;
endmodule

endpackage
