package ChannelSplitter;

import FIFO :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import Types :: *;

interface ChannelSplitter_ifc;

    interface Put#(YCbCr_t) pix;
    interface Get#(UInt#(8)) y;
    interface Get#(UInt#(8)) cb;
    interface Get#(UInt#(8)) cr;

endinterface

module mkChannelSplitter(ChannelSplitter_ifc);

    FIFO#(UInt#(8)) f_y     <- mkPipelineFIFO;
    FIFO#(UInt#(8)) f_cb    <- mkPipelineFIFO;
    FIFO#(UInt#(8)) f_cr    <- mkPipelineFIFO;

    interface Put pix;
        method Action put(YCbCr_t p);
            f_y.enq(p.y);
            f_cb.enq(p.cb);
            f_cr.enq(p.cr);
        endmethod
    endinterface

    interface y     = toGet(f_y);
    interface cb    = toGet(f_cb);
    interface cr    = toGet(f_cr);

endmodule

endpackage
