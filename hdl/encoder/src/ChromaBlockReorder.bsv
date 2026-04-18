package ChromaBlockReorder;

import FIFO :: *;
import BRAM :: *;
import GetPut :: *;
import SpecialFIFOs :: *;
import RegFile :: *;
import DefaultValue :: *;

import Types :: *;

interface ChromaBlockReorder_ifc;
    method Action rewind();
    method Action configure(SubsamplingMode_t mode, Bit#(13) blk_cols);

    interface Put#(UInt#(8)) pixel_in;
    interface Get#(UInt#(8)) pixel_out;
endinterface

module mkChromaBlockReorder#(NumProxy#(max_blk_cols) _)(ChromaBlockReorder_ifc)
    provisos(
        //BRAM for 4:2:0: one block-row of quarter-blocks (max_blk_cols * 16 pixels)
        NumAlias#(bram_cap, TMul#(max_blk_cols, 16)),
        NumAlias#(bram_aw, TLog#(bram_cap)),
        Add#(a__, bram_aw, 32)
    );

    FIFO#(UInt#(8)) f_in  <- mkPipelineFIFO;
    FIFO#(UInt#(8)) f_out <- mkPipelineFIFO;

    Reg#(SubsamplingMode_t) rg_mode     <- mkReg(YCBCR_444);
    Reg#(Bit#(13))          rg_blk_cols <- mkReg(0);

    // ---- 4:4:4 passthrough ----
    rule r_444 (rg_mode == YCBCR_444);
        let px = f_in.first; f_in.deq;
        f_out.enq(px);
    endrule

    //merge buffer
    RegFile#(Bit#(5), UInt#(8)) rf_merge <- mkRegFileFull;

    // ---- 4:2:2: merge two 4x8 half-blocks into one 8x8 DU ----
    Reg#(Bool)    rg_422_is_right  <- mkReg(False);
    Reg#(Bit#(5)) rg_422_store_idx <- mkReg(0);
    Reg#(Bit#(5)) rg_422_read_idx  <- mkReg(0);
    Reg#(Bit#(5)) rg_422_live_idx  <- mkReg(0);
    Reg#(Bool)    rg_422_emit_live <- mkReg(False);

    //store left half-block (32 pixels)
    rule r_422_store (rg_mode == YCBCR_422 && !rg_422_is_right);
        let px = f_in.first; f_in.deq;
        rf_merge.upd(rg_422_store_idx, px);
        if(rg_422_store_idx == 31) begin
            rg_422_store_idx <= 0;
            rg_422_is_right  <= True;
            rg_422_read_idx  <= 0;
            rg_422_live_idx  <= 0;
            rg_422_emit_live <= False;
        end else
            rg_422_store_idx <= rg_422_store_idx + 1;
    endrule

    //emit stored (left) row segment: 4 pixels
    rule r_422_emit_stored (rg_mode == YCBCR_422 && rg_422_is_right && !rg_422_emit_live);
        f_out.enq(rf_merge.sub(rg_422_read_idx));
        if(rg_422_read_idx[1:0] == 3)
            rg_422_emit_live <= True;
        rg_422_read_idx <= rg_422_read_idx + 1;
    endrule

    //emit live (right) row segment: 4 pixels
    rule r_422_emit_live (rg_mode == YCBCR_422 && rg_422_is_right && rg_422_emit_live);
        let px = f_in.first; f_in.deq;
        f_out.enq(px);
        if(rg_422_live_idx[1:0] == 3) begin
            rg_422_emit_live <= False;
            if (rg_422_live_idx == 31) begin
                //done with this DU pair
                rg_422_is_right  <= False;
                rg_422_store_idx <= 0;
                rg_422_live_idx  <= 0;
            end else
                rg_422_live_idx <= rg_422_live_idx + 1;
        end else
            rg_422_live_idx <= rg_422_live_idx + 1;
    endrule

    BRAM_Configure bram_cfg = defaultValue;
    bram_cfg.memorySize = valueOf(bram_cap);
    bram_cfg.latency = 1;
    BRAM1Port#(Bit#(bram_aw), UInt#(8)) bram <- mkBRAM1Server(bram_cfg);

    //TODO

    function Action reset_state();
        return action
            rg_422_is_right  <= False;
            rg_422_store_idx <= 0;
            rg_422_read_idx  <= 0;
            rg_422_live_idx  <= 0;
            rg_422_emit_live <= False;
        endaction;
    endfunction

    method Action configure(SubsamplingMode_t mode, Bit#(13) blk_cols);
        rg_mode     <= mode;
        rg_blk_cols <= blk_cols;
        reset_state();
    endmethod

    method Action rewind();
        reset_state();
    endmethod

    interface pixel_in  = toPut(f_in);
    interface pixel_out = toGet(f_out);

endmodule

endpackage
