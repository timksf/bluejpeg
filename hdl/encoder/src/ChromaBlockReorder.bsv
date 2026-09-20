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

typedef enum {
    C420StoreTop,
    C420StoreBottomLeft,
    C420EmitTop,
    C420EmitBottom
} Chroma420State_t deriving(Eq, Bits, FShow);

module mkChromaBlockReorder#(NumProxy#(max_blk_cols) _)(ChromaBlockReorder_ifc)
    provisos(
        // BRAM for 4:2:0: one block-row of quarter-blocks (max_blk_cols * 16 pixels)
        NumAlias#(bram_cap, TMul#(max_blk_cols, 16)),
        NumAlias#(bram_aw, TLog#(bram_cap)),
        Add#(a__, bram_aw, 32)
    );

    FIFO#(UInt#(8)) f_in  <- mkBypassFIFO;
    FIFO#(UInt#(8)) f_out <- mkFIFO;

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

    // ---- 4:2:0: merge four 4x4 quarter-blocks into one 8x8 DU ----
    Reg#(Chroma420State_t) rg_420_state        <- mkReg(C420StoreTop);
    Reg#(Bit#(13))         rg_420_blk_idx      <- mkReg(0);
    Reg#(Bit#(4))          rg_420_pix_idx      <- mkReg(0);
    Reg#(Bit#(5))          rg_420_top_idx      <- mkReg(0);
    Reg#(Bool)             rg_420_read_pending <- mkReg(False);
    Reg#(Bit#(4))          rg_420_left_idx     <- mkReg(0);
    Reg#(Bit#(4))          rg_420_right_idx    <- mkReg(0);
    Reg#(Bool)             rg_420_emit_right   <- mkReg(False);

    function Bit#(bram_aw) bram_addr(Bit#(13) blk, Bit#(4) pix);
        Bit#(32) addr = zeroExtend(blk) * 16 + zeroExtend(pix);
        return truncate(addr);
    endfunction

    // Store all top quarter-blocks for one 2x2 MCU row.
    rule r_420_store_top (rg_mode == YCBCR_420 && rg_420_state == C420StoreTop);
        let px = f_in.first; f_in.deq;
        bram.portA.request.put(BRAMRequest {
            write: True,
            responseOnWrite: False,
            address: bram_addr(rg_420_blk_idx, rg_420_pix_idx),
            datain: px
        });

        if(rg_420_pix_idx == 15) begin
            rg_420_pix_idx <= 0;
            if(rg_420_blk_idx == rg_blk_cols - 1) begin
                rg_420_blk_idx <= 0;
                rg_420_state   <= C420StoreBottomLeft;
            end else
                rg_420_blk_idx <= rg_420_blk_idx + 1;
        end else
            rg_420_pix_idx <= rg_420_pix_idx + 1;
    endrule

    // The bottom-left quarter must be buffered before its right neighbor arrives.
    rule r_420_store_bottom_left (rg_mode == YCBCR_420 && rg_420_state == C420StoreBottomLeft);
        let px = f_in.first; f_in.deq;
        rf_merge.upd(zeroExtend(rg_420_pix_idx), px);

        if(rg_420_pix_idx == 15) begin
            rg_420_pix_idx <= 0;
            rg_420_top_idx <= 0;
            rg_420_state   <= C420EmitTop;
        end else
            rg_420_pix_idx <= rg_420_pix_idx + 1;
    endrule

    // Read the two stored top quarters in 4-pixel row segments.
    rule r_420_top_req (rg_mode == YCBCR_420 && rg_420_state == C420EmitTop && !rg_420_read_pending);
        Bit#(13) src_blk = rg_420_blk_idx + zeroExtend(rg_420_top_idx[2]);
        Bit#(4) src_pix = {rg_420_top_idx[4:3], rg_420_top_idx[1:0]};
        bram.portA.request.put(BRAMRequest {
            write: False,
            responseOnWrite: False,
            address: bram_addr(src_blk, src_pix),
            datain: ?
        });
        rg_420_read_pending <= True;
    endrule

    rule r_420_top_resp (rg_mode == YCBCR_420 && rg_420_state == C420EmitTop && rg_420_read_pending);
        let px <- bram.portA.response.get();
        f_out.enq(px);
        rg_420_read_pending <= False;

        if(rg_420_top_idx == 31) begin
            rg_420_left_idx   <= 0;
            rg_420_right_idx  <= 0;
            rg_420_emit_right <= False;
            rg_420_state      <= C420EmitBottom;
        end else
            rg_420_top_idx <= rg_420_top_idx + 1;
    endrule

    // Interleave the buffered bottom-left and live bottom-right row segments.
    rule r_420_emit_bottom_left (rg_mode == YCBCR_420 && rg_420_state == C420EmitBottom && !rg_420_emit_right);
        f_out.enq(rf_merge.sub(zeroExtend(rg_420_left_idx)));
        if(rg_420_left_idx[1:0] == 3)
            rg_420_emit_right <= True;
        rg_420_left_idx <= rg_420_left_idx + 1;
    endrule

    rule r_420_emit_bottom_right (rg_mode == YCBCR_420 && rg_420_state == C420EmitBottom && rg_420_emit_right);
        let px = f_in.first; f_in.deq;
        f_out.enq(px);

        if(rg_420_right_idx[1:0] == 3) begin
            rg_420_emit_right <= False;
            if(rg_420_right_idx == 15) begin
                rg_420_left_idx  <= 0;
                rg_420_right_idx <= 0;
                if(rg_420_blk_idx == rg_blk_cols - 2) begin
                    rg_420_blk_idx <= 0;
                    rg_420_state   <= C420StoreTop;
                end else begin
                    rg_420_blk_idx <= rg_420_blk_idx + 2;
                    rg_420_state   <= C420StoreBottomLeft;
                end
            end else
                rg_420_right_idx <= rg_420_right_idx + 1;
        end else
            rg_420_right_idx <= rg_420_right_idx + 1;
    endrule

    function Action reset_state();
        return action
            rg_422_is_right  <= False;
            rg_422_store_idx <= 0;
            rg_422_read_idx  <= 0;
            rg_422_live_idx  <= 0;
            rg_422_emit_live <= False;

            rg_420_state        <= C420StoreTop;
            rg_420_blk_idx      <= 0;
            rg_420_pix_idx      <= 0;
            rg_420_top_idx      <= 0;
            rg_420_read_pending <= False;
            rg_420_left_idx     <= 0;
            rg_420_right_idx    <= 0;
            rg_420_emit_right   <= False;
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
