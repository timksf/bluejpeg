package DeZigZag;

import FIFO :: *;
import FIFOF :: *;
import Vector :: *;
import GetPut :: *;
import RegFile :: *;
import SpecialFIFOs :: *;

import ZigZag :: *;
import DecoderTypes :: *;

interface DeZigZag_ifc#(numeric type bits);
    interface Put#(DeqToken_t#(bits)) coef;
    interface Get#(Int#(bits))        sample;
    interface Get#(BlockTag_t)        tag;
endinterface

//blocks the buffer holds, more than two let the Huffman decoder run ahead through sparse blocks
typedef 4 DeZigZagBlocks;

/*
 * Inverse zigzag and block assembly, the counterpart of mkZigZag_Opt. The
 * sparse coefficient stream of one block is written to its natural position
 * in a ring of DeZigZagBlocks blocks in LUTRAM, and each block leaves one
 * coefficient per cycle in column-major order (row index u fastest), so the
 * IDCT gearbox collects columns. The read address is the read counter with
 * its halves swapped. Four blocks let the Huffman decoder run ahead through
 * sparse blocks and absorb symbol-dense ones that take longer than the 64
 * cycles a block needs downstream.
 *
 * A 64-bit valid mask per block replaces clearing, so coefficients that were
 * never written read as zero. The natural position is registered ahead of
 * the write, and the valid bit is registered with the coefficient read, so
 * the mask lookup and the zeroing are separate stages. The block tag (component, MCU end, frame end) is queued when a
 * block completes and rejoins the samples after the IDCT.
 */
module mkDeZigZag(DeZigZag_ifc#(bits));

    Vector#(64, UInt#(6)) dezigzag = map(fromInteger, zigzag_indices(False));

    RegFile#(Bit#(8), Int#(bits))           i_buf   <- mkRegFileWCF(0, 255);
    Vector#(DeZigZagBlocks, Reg#(Bit#(64))) rg_mask <- replicateM(mkReg(0));

    FIFO#(DeqToken_t#(bits))                    f_in  <- mkBypassFIFO;
    FIFO#(Tuple2#(DeqToken_t#(bits), UInt#(6))) f_idx <- mkFIFO;
    FIFO#(Tuple2#(Bool, Int#(bits)))            f_rd  <- mkFIFO;
    FIFO#(Int#(bits))                           f_out <- mkFIFO;
    FIFOF#(BlockTag_t)                          f_tag <- mkSizedFIFOF(8);

    Reg#(Bit#(2)) rg_wr_buf <- mkReg(0);
    Reg#(Bit#(2)) rg_rd_buf <- mkReg(0);
    Reg#(Bit#(6)) rg_rd_idx <- mkReg(0);

    Reg#(Bit#(3)) rg_blocks_written <- mkReg(0);
    Reg#(Bit#(3)) rg_blocks_read    <- mkReg(0);

    RWire#(Tuple2#(Bit#(2), UInt#(6))) w_set            <- mkRWire;
    RWire#(Bit#(2))                    w_clear          <- mkRWire;
    PulseWire                          pw_block_written <- mkPulseWire;
    PulseWire                          pw_block_read    <- mkPulseWire;

    Bit#(3) blocks_rdy = rg_blocks_written - rg_blocks_read;

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_count;
        if(pw_block_written) rg_blocks_written <= rg_blocks_written + 1;
        if(pw_block_read)    rg_blocks_read    <= rg_blocks_read + 1;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_mask;
        for(Integer b = 0; b < valueOf(DeZigZagBlocks); b = b + 1) begin
            Bit#(64) m = rg_mask[b];
            if(w_clear.wget == tagged Valid fromInteger(b)) m = 0;
            if(w_set.wget matches tagged Valid {.wb, .idx} &&& wb == fromInteger(b)) m[idx] = 1;
            rg_mask[b] <= m;
        end
    endrule

    //natural position from the zigzag ROM, registered ahead of the write
    rule r_index;
        let t = f_in.first; f_in.deq;
        f_idx.enq(tuple2(t, dezigzag[t.pos.k]));
    endrule

    rule r_write (blocks_rdy < fromInteger(valueOf(DeZigZagBlocks)));
        match {.t, .nat} = f_idx.first; f_idx.deq;
        if(t.has_val) begin
            i_buf.upd({rg_wr_buf, pack(nat)}, t.val);
            w_set.wset(tuple2(rg_wr_buf, nat));
        end
        if(t.pos.last) begin
            f_tag.enq(BlockTag_t {
                comp:    t.pos.comp,
                mcu_end: t.pos.mcu_end,
                last:    t.pos.last_block
            });
            rg_wr_buf <= rg_wr_buf + 1;
            pw_block_written.send;
        end
    endrule

    //column-major read, the natural index of (u, v) = (idx % 8, idx / 8) is u * 8 + v
    rule r_read (blocks_rdy > 0);
        Bit#(6) nat = {rg_rd_idx[2:0], rg_rd_idx[5:3]};
        f_rd.enq(tuple2(rg_mask[rg_rd_buf][nat] == 1, i_buf.sub({rg_rd_buf, nat})));
        if(rg_rd_idx == 63) begin
            rg_rd_buf <= rg_rd_buf + 1;
            w_clear.wset(rg_rd_buf);
            pw_block_read.send;
        end
        rg_rd_idx <= rg_rd_idx + 1;
    endrule

    //coefficients that were never written leave as zero
    rule r_emit;
        match {.valid, .val} = f_rd.first; f_rd.deq;
        f_out.enq(valid ? val : 0);
    endrule

    interface coef   = toPut(f_in);
    interface sample = toGet(f_out);
    interface tag    = toGet(f_tag);

endmodule

endpackage
