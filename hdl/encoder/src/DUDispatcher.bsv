package DUDispatcher;

import FIFO :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import Types :: *;

interface DUDispatcher_ifc;
    interface Put#(UInt#(8)) y;
    interface Put#(UInt#(8)) cb;
    interface Put#(UInt#(8)) cr;

    interface Get#(UInt#(8)) pix;
endinterface

//Dispatch one 8x8 DU per component in Y, Cb, Cr order.

module mkDUDispatcher(DUDispatcher_ifc);

    Reg#(Bit#(2)) rg_phase <- mkReg(0);
    Reg#(Bit#(6)) rg_count <- mkReg(0);

    FIFO#(UInt#(8)) f_out <- mkFIFO;
    FIFO#(UInt#(8)) f_cb  <- mkSizedFIFO(64);
    FIFO#(UInt#(8)) f_cr  <- mkSizedFIFO(64);

    function Bool is_y_phase  = (rg_phase == 0);
    function Bool is_cb_phase = (rg_phase == 1);
    function Bool is_cr_phase = (rg_phase == 2);

    function Action advance_phase();
        action
            rg_phase <= (rg_phase == 2) ? 0 : rg_phase + 1;
        endaction
    endfunction

    function Action fdispatch(UInt#(8) val);
        action
            f_out.enq(val);
            rg_count <= rg_count + 1;
            if (rg_count == 63)
                advance_phase();
        endaction
    endfunction

    //Buffer chroma while the splitter supplies the corresponding luma DU.
    rule r_dispatch_cb (is_cb_phase);
        fdispatch(f_cb.first);
        f_cb.deq;
    endrule

    rule r_dispatch_cr (is_cr_phase);
        fdispatch(f_cr.first);
        f_cr.deq;
    endrule

    interface y     = toPut(when(is_y_phase,  fdispatch));
    interface cb    = toPut(f_cb);
    interface cr    = toPut(f_cr);

    interface pix   = toGet(f_out);
endmodule

endpackage
