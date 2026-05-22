package DCT2D_Optimized;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import RegFile :: *;
import Connectable :: *;
import SpecialFIFOs :: *;
import ClientServer :: *;

import Util :: *;
import Types :: *;
import DCT1D :: *;
import DCT2D :: *;
import TransposeBuffer :: *;

interface DCT2DOpt_ifc#(numeric type bits);
    method Action rewind();
    method Bool overflow();
    interface Server#(Vector#(8, Int#(bits)), Vector#(8, Int#(bits))) data;
endinterface

module mkDCT2D_Opt#(NumProxy#(frac_bits) f_scale, Bool buffer_in, Bool omit_scaling, Bool transpose_output, Bool dct_safe_arith)(DCT2DOpt_ifc#(bits));

    FIFO#(Vector#(8, Int#(bits))) f_in;
    FIFO#(Vector#(8, Int#(bits))) f_out <- mkPipelineFIFO;

    if(buffer_in)
        f_in <- mkPipelineFIFO;
    else
        f_in <- mkBypassFIFO;

    DCT1D_ifc#(bits) dct_row <- mkDCT1D(f_scale, !omit_scaling, dct_safe_arith);
    DCT1D_ifc#(bits) dct_col <- mkDCT1D(f_scale, !omit_scaling, dct_safe_arith);

    TransposeBufferOpt_ifc#(Int#(bits)) tp0 <- mkTransposeBufferOpt;
    TransposeBufferOpt_ifc#(Int#(bits)) tp1 = ?;
    if (transpose_output) tp1 <- mkTransposeBufferOpt;

    //row DCT
    mkConnection(toGet(f_in), dct_row.data.request);
    
    //transpose
    mkConnection(dct_row.data.response, tp0.original);
    
    //col DCT
    mkConnection(tp0.transposed, dct_col.data.request);

    //output directly or transpose again
    if (!transpose_output) begin
        mkConnection(dct_col.data.response, toPut(f_out));
    end else begin
        mkConnection(dct_col.data.response, tp1.original);
        mkConnection(tp1.transposed, toPut(f_out));
    end

    method Action rewind();
        tp0.rewind();
        if (transpose_output) tp1.rewind();
    endmethod

    method overflow = dct_row.overflow || dct_col.overflow;

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage