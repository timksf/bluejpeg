package TransposeBuffer;

import BRAM :: *;
import DefaultValue :: *;
import ClientServer :: *;
import Vector :: *;
import FIFO :: *;
import GetPut :: *;
import RegFile :: *;

import Types :: *;
import PrintUtil :: *;
import Util :: *;

interface TransposeBuffer_ifc#(type t, numeric type w, numeric type h);
    method Action rewind();

    interface Put#(t) original;
    interface Get#(t) transposed;
endinterface

//TODO add wide input version (not serialized to the individual element)
//TODO add double buffering and BRAM option
module mkTransposeBuffer#(Bool use_bram)(TransposeBuffer_ifc#(t, w, h))
    provisos(
        Bits#(t, a__),
        FShow#(t),
        Log#(w, hori_idx_w),
        Log#(h, vert_idx_w)
    );

    Integer width   = valueof(w);
    Integer height  = valueof(h);
    Bit#(hori_idx_w) max_hori_idx = fromInteger(width-1);
    Bit#(vert_idx_w) max_vert_idx = fromInteger(height-1);

    Vector#(TMul#(w, h), Reg#(t)) vBuffer <- replicateM(mkRegU);

    Reg#(Bit#(vert_idx_w))  rg_read_i   <- mkRegU;
    Reg#(Bit#(hori_idx_w))  rg_read_j   <- mkRegU;
    Reg#(Bit#(hori_idx_w))  rg_write_i  <- mkRegU;
    Reg#(Bit#(vert_idx_w))  rg_write_j  <- mkRegU;
    Reg#(Bool)              rg_filled   <- mkRegU;
    Reg#(Bool)              rg_empty    <- mkRegU;
    PulseWire               pw_rewind   <- mkPulseWire;

    method Action rewind();
        rg_read_i <= 0;
        rg_read_j <= 0;
        rg_write_i <= 0;
        rg_write_j <= 0;
        rg_filled <= False;
        rg_empty <= False;
    endmethod

    interface Put original;
        method Action put(t d) if(!rg_filled && !pw_rewind);
            if(rg_write_i == max_hori_idx) begin
                rg_write_i <= 0;
                rg_write_j <= rg_write_j + 1;
                if(rg_write_j == max_vert_idx) begin
                    rg_filled <= True;
                end
            end else begin
                rg_write_i <= rg_write_i + 1;
            end
            Bit#(TAdd#(hori_idx_w,vert_idx_w)) idx = extend(rg_write_i)+extend(rg_write_j)*fromInteger(width);
            // $display(fshow(readVReg(vBuffer)));
            vBuffer[idx] <= d;
        endmethod
    endinterface

    interface Get transposed;
        method ActionValue#(t) get() if(rg_filled && !pw_rewind && !rg_empty);
            Bit#(TAdd#(hori_idx_w,vert_idx_w)) idx = extend(rg_read_j)+extend(rg_read_i)*fromInteger(width);
            let d = vBuffer[idx];
            /* advance indices with transposed limits (first vert, then hori) */
            // $display("Read %0d, %0d", rg_read_j, rg_read_i);
            if(rg_read_i == max_vert_idx) begin
                rg_read_i <= 0;
                rg_read_j <= rg_read_j + 1;
                if(rg_read_j == max_hori_idx) begin
                    rg_empty <= True;
                end
            end else begin
                rg_read_i <= rg_read_i + 1;
            end

            return d;
        endmethod
    endinterface

endmodule

interface TransposeBufferOpt_ifc#(type t);
    method Action rewind();

    interface Put#(Vector#(8, t)) original;
    interface Get#(Vector#(8, t)) transposed;
endinterface

/*
    
    Skewed/diagonal buffering lets us write an entire row at once - but also read an entire
    row at once.

    Bank 0: [ r0_0 r1_7 r2_6 r3_5 r4_4 r5_3 r6_2 r7_1 ; XX XX XX XX XX XX XX XX ]
    Bank 1: [ r0_1 r1_0 r2_7 r3_6 r4_5 r5_4 r6_3 r7_2 ; XX XX XX XX XX XX XX XX ]
    Bank 2: [ r0_2 r1_1 r2_0 r3_7 r4_6 r5_5 r6_4 r7_3 ; XX XX XX XX XX XX XX XX ]
    Bank 3: [ r0_3 r1_2 r2_1 r3_0 r4_7 r5_6 r6_5 r7_4 ; XX XX XX XX XX XX XX XX ]
    Bank 4: [ r0_4 r1_3 r2_2 r3_1 r4_0 r5_7 r6_6 r7_5 ; XX XX XX XX XX XX XX XX ]
    Bank 5: [ r0_5 r1_4 r2_3 r3_2 r4_1 r5_0 r6_7 r7_6 ; XX XX XX XX XX XX XX XX ]
    Bank 6: [ r0_6 r1_5 r2_4 r3_3 r4_2 r5_1 r6_0 r7_7 ; XX XX XX XX XX XX XX XX ]
    Bank 7: [ r0_7 r1_6 r2_5 r3_4 r4_3 r5_2 r6_1 r7_0 ; XX XX XX XX XX XX XX XX ]

*/

//optimized version of transpose buffer working on line-granularity for input/output
module mkTransposeBufferOpt(TransposeBufferOpt_ifc#(t)) provisos(Bits#(t, __st));

    //buffer layout see below, 2 buffers total for ping-pong
    //each with 8 banks that are filled diagonally
    Vector#(8, RegFile#(Bit#(4), t)) banks <- replicateM(mkRegFile(0, 15));

    Reg#(Bit#(1)) rg_wr_buf <- mkReg(0);
    Reg#(Bit#(3)) rg_wr_row <- mkReg(0);

    Reg#(Bit#(1)) rg_rd_buf <- mkReg(0);
    Reg#(Bit#(3)) rg_rd_col <- mkReg(0);

    Reg#(Bit#(2)) rg_blocks_written <- mkReg(0);
    Reg#(Bit#(2)) rg_blocks_read    <- mkReg(0);

    Bit#(2) blocks_rdy = rg_blocks_written - rg_blocks_read;

    method Action rewind();
        rg_wr_buf <= 0;
        rg_wr_row <= 0;
        rg_rd_buf <= 0;
        rg_rd_col <= 0;
        rg_blocks_written <= 0;
        rg_blocks_read <= 0;
    endmethod

    interface Put original;

        method Action put(Vector#(8, t) row) if (blocks_rdy < 2);
            // Iterate statically over banks to infer exactly 1 write port per bank
            for (Integer b = 0; b < 8; b = b + 1) begin
                Bit#(3) col_idx = fromInteger(b) - rg_wr_row;
                banks[b].upd({rg_wr_buf, rg_wr_row}, row[col_idx]);
            end

            if (rg_wr_row == 7) begin
                rg_wr_row <= 0;
                rg_wr_buf <= ~rg_wr_buf;
                rg_blocks_written <= rg_blocks_written + 1;
            end else begin
                rg_wr_row <= rg_wr_row + 1;
            end
        endmethod

    endinterface

    interface Get transposed;

        method ActionValue#(Vector#(8, t)) get() if (blocks_rdy > 0);
            Vector#(8, t) bank_reads = newVector;
            
            //iterate statically over banks to infer exactly 1 read port per bank
            for (Integer b = 0; b < 8; b = b + 1) begin
                Bit#(3) r_idx = fromInteger(b) - rg_rd_col;
                bank_reads[b] = banks[b].sub({rg_rd_buf, r_idx});
            end

            Vector#(8, t) col = newVector;
            for (Integer r = 0; r < 8; r = r + 1) begin
                Bit#(3) bank_idx = (fromInteger(r) + rg_rd_col);
                col[r] = bank_reads[bank_idx];
            end

            if (rg_rd_col == 7) begin
                rg_rd_col <= 0;
                rg_rd_buf <= ~rg_rd_buf;
                rg_blocks_read <= rg_blocks_read + 1;
            end else begin
                rg_rd_col <= rg_rd_col + 1;
            end
            return col;
        endmethod

    endinterface

endmodule


endpackage