package DCT2D;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import Connectable :: *;
import SpecialFIFOs :: *;
import ClientServer :: *;

import EncoderUtil :: *;
import Types :: *;
import DCT1D :: *;
import TransposeBuffer :: *;

interface DCT2D_ifc#(numeric type bits);
    method Action rewind();
    interface Server#(DU_t#(Int#(bits), 8, 8), DU_t#(Int#(bits), 8, 8)) data;
endinterface

//TODO optimize resource usage (especially register usage!)
module mkDCT2D#(NumProxy_t#(frac_bits) f_scale, Bool transpose_output)(DCT2D_ifc#(bits));

    FIFO#(DU_t#(Int#(bits), 8, 8)) f_in  <- mkPipelineFIFO;
    FIFO#(DU_t#(Int#(bits), 8, 8)) f_out <- mkPipelineFIFO;

    DCT1D_ifc#(bits) i_dct_row <- mkDCT1D(f_scale, False, True);
    DCT1D_ifc#(bits) i_dct_col <- mkDCT1D(f_scale, False, True);

    TransposeBuffer_ifc#(Int#(bits), 8, 8) i_tp0 <- mkTransposeBuffer(False);
    TransposeBuffer_ifc#(Int#(bits), 8, 8) i_tp1 = ?;

    if(transpose_output) begin
        i_tp1 <- mkTransposeBuffer(False);
    end

    Reg#(Bit#(3)) rg_row <- mkReg(0);

    //after reading the output of the row DCT, serialize into transpose buffer
    Reg#(Vector#(8, Int#(bits))) rg_row_buf   <- mkRegU;
    Reg#(Bit#(3))                rg_col_idx   <- mkReg(0);
    Reg#(Bool)                   rg_row_valid <- mkReg(False);

    //de-serialize from transpose buffer and then perform col dct
    Reg#(Vector#(8, Int#(bits))) rg_col_buf <- mkRegU;
    Reg#(Bit#(3))                rg_row_idx <- mkReg(0);
    Reg#(Bit#(6))                rg_tp_cnt  <- mkReg(0);

    PulseWire pw_rewind <- mkPulseWire;

    //row DCT
    rule r_row_dct;
        let mcu = f_in.first;
        i_dct_row.data.request.put(mcu.block[rg_row]);
        if(rg_row == 7) begin
            rg_row <= 0;
            f_in.deq;
        end else begin
            rg_row <= rg_row + 1;
        end
    endrule

    //transpose buffer serialization
    rule r_row_dct_res (!rg_row_valid);
        let v <- i_dct_row.data.response.get();
        rg_row_buf <= v;
        rg_row_valid <= True;
        rg_col_idx <= 0;
    endrule

    rule r_transpose_main (rg_row_valid);
        i_tp0.original.put(rg_row_buf[rg_col_idx]);
        if(rg_col_idx == 7) begin
            rg_row_valid <= False;
        end
        rg_col_idx <= rg_col_idx + 1;
    endrule

    //transpose de-serialization -> col dct
    rule r_col_dct;
        let val <- i_tp0.transposed.get();
        rg_col_buf[rg_row_idx] <= val;

        if(rg_row_idx == 7) begin
            let new_vec = rg_col_buf;
            new_vec[7] = val;
            i_dct_col.data.request.put(new_vec);

            if(rg_tp_cnt == 63) begin
                // i_tp0.rewind();
                rg_tp_cnt <= 0;
            end else begin
                rg_tp_cnt <= rg_tp_cnt + 1;
            end
            rg_row_idx <= 0;
        end else begin
            rg_row_idx <= rg_row_idx + 1;
        end
    endrule

    //output - reassemble into (transposed) DU_t
    if(!transpose_output) begin
        //no output transpose
        Reg#(Vector#(8, Vector#(8, Int#(bits)))) rg_mcu_out     <- mkRegU;
        Reg#(Bit#(3))                            rg_out_col_idx <- mkReg(0);

        rule r_build_out;
            let v <- i_dct_col.data.response.get();
            rg_mcu_out[rg_out_col_idx] <= v;

            if(rg_out_col_idx == 7) begin
                let final_block = rg_mcu_out;
                final_block[7] = v;
                f_out.enq(DU_t { block: final_block });
                rg_out_col_idx <= 0;
            end else begin
                rg_out_col_idx <= rg_out_col_idx + 1;
            end
        endrule

        rule r_rewind (pw_rewind);
            rg_out_col_idx <= 0;
        endrule

    end else begin
        //output transpose enabled

        //serialize
        // Reg#(Vector#(8, Int#(bits))) rVecBuf2 <- mkRegU;
        // Reg#(Bit#(3)) rVecIdx2 <- mkReg(0);
        // Reg#(Bool) rVecValid2 <- mkReg(False);

        // rule get_dct_row_out if (!rVecValid2);
        //     let v <- i_dct_col.data.response.get();
        //     rVecBuf2 <= v;
        //     rVecValid2 <= True;
        //     rVecIdx2 <= 0;
        // endrule

        // rule feed_trans_2 if (rVecValid2);
        //     i_tp1.original.put(rVecBuf2[rVecIdx2]);
        //     if (rVecIdx2 == 7) rVecValid2 <= False;
        //     rVecIdx2 <= rVecIdx2 + 1;
        // endrule

        //// 4b. Collect Final Output (Deserialize from Transpose 2)
        // Reg#(Vector#(8, Vector#(8, Int#(bits)))) rFinalBlock <- mkRegU;
        // Reg#(Vector#(8, Int#(bits))) rFinalRow <- mkRegU;
        // Reg#(Bit#(3)) rFinalColIdx <- mkReg(0);
        // Reg#(Bit#(3)) rFinalRowIdx <- mkReg(0);
        // Reg#(Bit#(6)) rTrans2Cnt <- mkReg(0);

        // rule collect_output_transposed;
        //     let val <- i_tp1.transposed.get();
        //     rFinalRow[rFinalColIdx] <= val;

        //     if (rFinalColIdx == 7) begin
        //         let row_vec = rFinalRow;
        //         row_vec[7] = val;
        //         rFinalBlock[rFinalRowIdx] <= row_vec;

        //         if (rFinalRowIdx == 7) begin
        //             let block = rFinalBlock;
        //             block[7] = row_vec;
        //             f_out.enq(DU_t { block: block });
        //             rFinalRowIdx <= 0;
        //         end else begin
        //             rFinalRowIdx <= rFinalRowIdx + 1;
        //         end
        //         rFinalColIdx <= 0;
        //     end else begin
        //         rFinalColIdx <= rFinalColIdx + 1;
        //     end

        //     if (rTrans2Cnt == 63) begin
        //         i_tp1.rewind();
        //         rTrans2Cnt <= 0;
        //     end else begin
        //         rTrans2Cnt <= rTrans2Cnt + 1;
        //     end
        // endrule

        // rule r_rewind if(pw_rewind);
        //     rVecIdx2 <= 0;
        //     rVecValid2 <= False;
        //     rFinalColIdx <= 0;
        //     rFinalRowIdx <= 0;
        //     rTrans2Cnt <= 0;
        // endrule
    end

    method Action rewind();
        rg_row <= 0;
        rg_col_idx <= 0;
        rg_row_valid <= False;
        rg_row_idx <= 0;
        rg_tp_cnt <= 0;
        i_tp0.rewind();
        if(transpose_output) i_tp1.rewind();
        pw_rewind.send();
    endmethod

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage
