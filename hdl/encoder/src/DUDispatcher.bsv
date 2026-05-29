package DUDispatcher;

import FIFO :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import Types :: *;

interface DUDispatcher_ifc;
    method Action set_mode(SubsamplingMode_t mode);

    interface Put#(UInt#(8)) y;
    interface Put#(UInt#(8)) cb;
    interface Put#(UInt#(8)) cr;

    interface Get#(UInt#(8)) pix;
endinterface

//dispatch phases for correct subsampling:
//  0..3 = Y blocks (count depends on mode)
//  4    = Cb
//  5    = Cr

module mkDUDispatcher(DUDispatcher_ifc);

    Reg#(Bit#(3)) rg_phase <- mkReg(0);
    Reg#(Bit#(6)) rg_count <- mkReg(0);

    Reg#(SubsamplingMode_t) rg_mode <- mkRegU;

    FIFO#(UInt#(8)) f_out <- mkFIFO;

    function Bool is_y_phase  = (rg_phase <= 3);
    function Bool is_cb_phase = (rg_phase == 4);
    function Bool is_cr_phase = (rg_phase == 5);

    function Action advance_phase();
        action
            if (rg_phase == 0 && rg_mode == YCBCR_444 || rg_phase == 1 && rg_mode == YCBCR_422)
                rg_phase <= 4;
            else if (rg_phase < 5)
                rg_phase <= rg_phase + 1;
            else
                rg_phase <= 0;
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

    method set_mode = rg_mode._write;

    interface y     = toPut(when(is_y_phase,  fdispatch));
    interface cb    = toPut(when(is_cb_phase, fdispatch));
    interface cr    = toPut(when(is_cr_phase, fdispatch));

    interface pix   = toGet(f_out);
endmodule

endpackage
