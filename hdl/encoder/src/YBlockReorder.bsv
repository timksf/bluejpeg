package YBlockReorder;

import FIFO :: *;
import BRAM :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import Types :: *;

//Reorders Y blocks from raster order to 4:2:0 MCU order for interleaved ordering according to A.2.3.
//
//Input (raster):  row0[0] row0[1] row0[2] ... row1[0] row1[1] row1[2] ...
//Output (MCU):    row0[0] row0[1] row1[0] row1[1] row0[2] row0[3] row1[2] row1[3] ...
//
//Even block-rows are stored into BRAM.
//Odd block-rows: emit stored pair then live pair, alternating.
//
//In 4:4:4 and 4:2:2 modes, passthrough (no reordering needed).
//
//max_blk_cols: maximum number of 8x8 blocks per row (= max_img_width / 8)

interface YBlockReorder_ifc;
    method Action rewind();
    method Action configure(SubsamplingMode_t mode, Bit#(13) blk_cols);

    interface Put#(UInt#(8)) pixel_in;
    interface Get#(UInt#(8)) pixel_out;
endinterface

module mkYBlockReorder#(NumProxy#(max_blk_cols) _, Bool buffer_in)(YBlockReorder_ifc)
    provisos(
        //BRAM address width: ceil(log2(max_blk_cols * 64)), supports non-power-of-2 sizes
        NumAlias#(bram_addr_w, TLog#(TMul#(max_blk_cols, 64))),
        Add#(a__, bram_addr_w, 32)
    );

    FIFO#(UInt#(8)) f_in;
    FIFO#(UInt#(8)) f_out <- mkFIFO;

    if(buffer_in)
        f_in <- mkFIFO;
    else
        f_in <- mkBypassFIFO;

    //BRAM for storing one block-row of Y pixels
    BRAM_Configure cfg = defaultValue;
    cfg.memorySize = valueOf(TMul#(max_blk_cols, 64));
    cfg.latency = 1;
    BRAM1Port#(Bit#(bram_addr_w), UInt#(8)) bram <- mkBRAM1Server(cfg);

    //configuration
    Reg#(SubsamplingMode_t) rg_mode      <- mkReg(YCBCR_444);
    Reg#(Bit#(13))          rg_blk_cols  <- mkReg(0);  //number of 8x8 block columns (img_width / 8)

    //state
    Reg#(Bool)      rg_row_odd  <- mkReg(False);  //even/odd block-row
    Reg#(Bit#(13))  rg_blk_idx  <- mkReg(0);      //current block index within block-row
    Reg#(Bit#(6))   rg_pix_idx  <- mkReg(0);      //pixel index within current block (0..63)

    //output phase for odd rows: False = reading stored pair, True = forwarding live pair
    Reg#(Bool)      rg_out_live <- mkReg(False);
    Reg#(Bit#(13))  rg_out_blk  <- mkReg(0);      //output block index
    Reg#(Bit#(6))   rg_out_pix  <- mkReg(0);      //output pixel index within block

    //address for a pixel within a stored block-row
    function Bit#(bram_addr_w) bram_addr(Bit#(13) blk, Bit#(6) pix);
        Bit#(32) addr = zeroExtend(blk) * 64 + zeroExtend(pix);
        return truncate(addr);
    endfunction

    //passthrough for 4:4:4 and 4:2:2
    rule r_passthrough (rg_mode != YCBCR_420);
        let px = f_in.first; f_in.deq;
        f_out.enq(px);
    endrule

    //4:2:0, even block-row: store all pixels into BRAM
    rule r_store (rg_mode == YCBCR_420 && !rg_row_odd);
        let px = f_in.first; f_in.deq;

        bram.portA.request.put(BRAMRequest {
            write: True,
            responseOnWrite: False,
            address: bram_addr(rg_blk_idx, rg_pix_idx),
            datain: px
        });

        if (rg_pix_idx == 63) begin
            rg_pix_idx <= 0;
            if (rg_blk_idx == rg_blk_cols - 1) begin
                rg_blk_idx <= 0;
                rg_row_odd <= True;
                //prepare output state: start with stored block 0
                rg_out_live <= False;
                rg_out_blk  <= 0;
                rg_out_pix  <= 0;
            end else
                rg_blk_idx <= rg_blk_idx + 1;
        end else
            rg_pix_idx <= rg_pix_idx + 1;
    endrule

    //4:2:0, odd block-row, stored phase: read stored blocks from BRAM
    //emit two consecutive stored blocks, then switch to live
    rule r_read_req (rg_mode == YCBCR_420 && rg_row_odd && !rg_out_live);
        bram.portA.request.put(BRAMRequest {
            write: False,
            responseOnWrite: False,
            address: bram_addr(rg_out_blk, rg_out_pix),
            datain: ?
        });
    endrule

    rule r_read_resp (rg_mode == YCBCR_420 && rg_row_odd && !rg_out_live);
        let px <- bram.portA.response.get();
        f_out.enq(px);

        if (rg_out_pix == 63) begin
            rg_out_pix <= 0;
            //after two stored blocks (even, odd of pair), switch to live
            if (rg_out_blk[0] == 1)
                rg_out_live <= True;
            rg_out_blk <= rg_out_blk + 1;
        end else
            rg_out_pix <= rg_out_pix + 1;
    endrule

    //4:2:0, odd block-row, live phase: forward incoming blocks from tiling engine
    //forward two consecutive live blocks, then switch back to stored
    rule r_forward (rg_mode == YCBCR_420 && rg_row_odd && rg_out_live);
        let px = f_in.first; f_in.deq;
        f_out.enq(px);

        if (rg_pix_idx == 63) begin
            rg_pix_idx <= 0;
            if (rg_blk_idx[0] == 1) begin
                //finished two live blocks, switch back to stored (or end of row)
                rg_out_live <= False;
                if (rg_blk_idx == rg_blk_cols - 1) begin
                    //end of odd block-row, reset for next even row
                    rg_blk_idx  <= 0;
                    rg_row_odd  <= False;
                    rg_out_blk  <= 0;
                    rg_out_pix  <= 0;
                end else
                    rg_blk_idx <= rg_blk_idx + 1;
            end else
                rg_blk_idx <= rg_blk_idx + 1;
        end else
            rg_pix_idx <= rg_pix_idx + 1;
    endrule

    method Action configure(SubsamplingMode_t mode, Bit#(13) blk_cols);
        rg_mode     <= mode;
        rg_blk_cols <= blk_cols;
        rg_row_odd  <= False;
        rg_blk_idx  <= 0;
        rg_pix_idx  <= 0;
        rg_out_live <= False;
        rg_out_blk  <= 0;
        rg_out_pix  <= 0;
    endmethod

    method Action rewind();
        rg_row_odd  <= False;
        rg_blk_idx  <= 0;
        rg_pix_idx  <= 0;
        rg_out_live <= False;
        rg_out_blk  <= 0;
        rg_out_pix  <= 0;
    endmethod

    interface pixel_in  = toPut(f_in);
    interface pixel_out = toGet(f_out);

endmodule

endpackage
