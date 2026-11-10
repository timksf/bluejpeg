package DCT2D_Optimized;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import RegFile :: *;
import Connectable :: *;
import SpecialFIFOs :: *;
import ClientServer :: *;

import EncoderUtil :: *;
import Types :: *;
import DCT1D :: *;
import DCT2D :: *;
import TransposeBuffer :: *;

interface DCT2DOpt_ifc#(numeric type bits);
    method Action rewind();
    method Bool overflow();
    interface Server#(Vector#(8, Int#(bits)), Vector#(8, Int#(bits))) data;
endinterface

//bits is B, the signed width of a centered JPEG sample
interface DCT2DOptRigid_ifc#(numeric type bits);
    method Action rewind();
    method Bool overflow();
    interface Server#(Vector#(8, Int#(bits)), Vector#(8, Int#(TAdd#(bits, 7)))) data;
endinterface

module mkDCT2D_Opt#(NumProxy_t#(frac_bits) f_scale, Bool buffer_in, Bool omit_scaling, Bool transpose_output, Bool dct_safe_arith)(DCT2DOpt_ifc#(bits));

    FIFO#(Vector#(8, Int#(bits))) f_in;
    FIFO#(Vector#(8, Int#(bits))) f_out <- mkFIFO;

    if(buffer_in)
        f_in <- mkFIFO;
    else
        f_in <- mkBypassFIFO;

    DCT1D_ifc#(bits) i_dct_row <- mkDCT1D(f_scale, !omit_scaling, dct_safe_arith);
    DCT1D_ifc#(bits) i_dct_col <- mkDCT1D(f_scale, !omit_scaling, dct_safe_arith);

    TransposeBufferOpt_ifc#(Int#(bits)) i_tp0 <- mkTransposeBufferOpt;
    TransposeBufferOpt_ifc#(Int#(bits)) i_tp1 = ?;
    if(transpose_output) i_tp1 <- mkTransposeBufferOpt;

    //row DCT
    mkConnection(toGet(f_in), i_dct_row.data.request);

    //transpose
    mkConnection(i_dct_row.data.response, i_tp0.original);

    //col DCT
    mkConnection(i_tp0.transposed, i_dct_col.data.request);

    //output directly or transpose again
    if(!transpose_output) begin
        mkConnection(i_dct_col.data.response, toPut(f_out));
    end else begin
        mkConnection(i_dct_col.data.response, i_tp1.original);
        mkConnection(i_tp1.transposed, toPut(f_out));
    end

    method Action rewind();
        i_tp0.rewind();
        if(transpose_output) i_tp1.rewind();
    endmethod

    method overflow = i_dct_row.overflow || i_dct_col.overflow;

    interface data = toGPServer(f_in, f_out);

endmodule

module mkDCT2D_Opt_rigid#(NumProxy_t#(frac_bits) f_scale, Bool buffer_in, Bool omit_scaling, Bool transpose_output, Bool dct_safe_arith)(DCT2DOptRigid_ifc#(bits));

    FIFO#(Vector#(8, Int#(bits)))           f_in;
    FIFO#(Vector#(8, Int#(TAdd#(bits, 7)))) f_out <- mkFIFO;

    if(buffer_in)
        f_in <- mkFIFO;
    else
        f_in <- mkBypassFIFO;

    DCT1D_ifc#(TAdd#(bits, 4)) i_dct_row <- mkDCT1D_rigid(f_scale, !omit_scaling, dct_safe_arith);
    DCT1D_ifc#(TAdd#(bits, 7)) i_dct_col <- mkDCT1D_rigid(f_scale, !omit_scaling, dct_safe_arith);

    TransposeBufferOpt_ifc#(Int#(TAdd#(bits, 4))) i_tp0 <- mkTransposeBufferOpt;
    TransposeBufferOpt_ifc#(Int#(TAdd#(bits, 7))) i_tp1 = ?;
    if(transpose_output) i_tp1 <- mkTransposeBufferOpt;

    //row DCT
    rule r_row_dct_input;
        let row = f_in.first;
        f_in.deq;
        i_dct_row.data.request.put(map(signExtend, row));
    endrule

    //transpose
    mkConnection(i_dct_row.data.response, i_tp0.original);

    //col DCT
    rule r_col_dct_input;
        let col <- i_tp0.transposed.get;
        i_dct_col.data.request.put(map(signExtend, col));
    endrule

    //output directly or transpose again
    if(!transpose_output) begin
        mkConnection(i_dct_col.data.response, toPut(f_out));
    end else begin
        mkConnection(i_dct_col.data.response, i_tp1.original);
        mkConnection(i_tp1.transposed, toPut(f_out));
    end

    method Action rewind();
        i_tp0.rewind();
        if(transpose_output) i_tp1.rewind();
    endmethod

    method overflow = i_dct_row.overflow || i_dct_col.overflow;

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage
