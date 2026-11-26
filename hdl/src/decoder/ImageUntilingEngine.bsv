package ImageUntilingEngine;

import BRAM :: *;
import FIFO :: *;
import FIFOF :: *;
import Vector :: *;
import GetPut :: *;
import SpecialFIFOs :: *;
import DefaultValue :: *;

import Types :: *;
import DecoderTypes :: *;

interface ImageUntilingEngine_ifc;
    interface Put#(FrameInfo_t) frame;
    interface Put#(PixelOut_t)  pix_in;
    interface Get#(PixelOut_t)  pix_out;
endinterface

//geometry of one frame, derived once when the frame starts
typedef struct {
    UInt#(bx_w) bx_last;
    UInt#(x_w)  x_last;
    UInt#(3)    line_last;
} UntileGeometry_t#(numeric type bx_w, numeric type x_w) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(1)    buffer;
    UInt#(3)   line_last;
    UInt#(x_w) x_last;
    Bool       last;
} UntileGroup_t#(numeric type x_w) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(1) buffer;
    Bool    group_last;
    Bool    frame_last;
} UntileRead_t deriving(Bits, Eq, FShow);

/*
 * Output stage, the inverse of the encoder's mkImageTilingEngine. With
 * enable, pixels arriving in block order are collected per MCU row (a group
 * of eight lines) and read back in raster order, one pixel per cycle, cropped
 * to the frame size. Without enable, pixels pass through in block order like
 * the encoder expects them without its tiler, and the frame geometry is
 * dropped.
 */
module mkImageUntilingEngine#(NumProxy_t#(max_img_width) p, Bool enable, Bool double_buffer)(ImageUntilingEngine_ifc)
    provisos(
        NumAlias#(TLog#(TDiv#(TAdd#(max_img_width, 7), 8)), bx_w),
        Add#(bx_w, a__, 13)
    );
    ImageUntilingEngine_ifc ifc;
    if(enable)
        ifc <- mkImageUntilingEngineActive(p, double_buffer);
    else
        ifc <- mkImageUntilingEngineBypass;
    return ifc;
endmodule

/*
 * Line buffer of 24-bit pixels addressed by {buffer, line, x}. In block order
 * the pixel index p within a block gives line = p / 8 and x = 8 * bx + p % 8,
 * so the write address is {buffer, p[5:3], bx, p[2:0]} and raster reads walk
 * {buffer, line, x} linearly. The writer fills one group, hands its
 * descriptor to the reader and marks the buffer busy until the reader has
 * consumed its last pixel. With double_buffer the writer continues into the
 * second buffer meanwhile. Read metadata travels in a FIFO next to the BRAM
 * responses, which the BRAM server throttles by credit, and the BRAM output
 * register is enabled. Frame geometry is derived once per frame, so the
 * streaming rules only compare counters with registers.
 */
module mkImageUntilingEngineActive#(NumProxy_t#(max_img_width) _p, Bool double_buffer)(ImageUntilingEngine_ifc)
    provisos(
        NumAlias#(TLog#(TDiv#(TAdd#(max_img_width, 7), 8)), bx_w),
        NumAlias#(TAdd#(bx_w, 3), x_w),
        NumAlias#(TAdd#(x_w, 4), addr_w),
        Add#(bx_w, a__, 13),
        Add#(x_w, b__, 16)
    );

    Integer n_buffers = double_buffer ? 2 : 1;

    BRAM_Configure bram_cfg = defaultValue;
    bram_cfg.memorySize   = n_buffers * 8 * (2 ** valueOf(x_w));
    bram_cfg.latency      = 2;
    bram_cfg.outFIFODepth = 4;

    BRAM2Port#(Bit#(addr_w), YCbCr_t) i_mem <- mkBRAM2Server(bram_cfg);

    FIFO#(FrameInfo_t)                   f_frame <- mkFIFO;
    FIFO#(UntileGeometry_t#(bx_w, x_w))  f_geom  <- mkFIFO;
    FIFO#(PixelOut_t)                    f_in    <- mkBypassFIFO;
    FIFO#(UntileGroup_t#(x_w))           f_group <- mkSizedFIFO(2);
    FIFO#(UntileRead_t)                  f_meta  <- mkSizedFIFO(5);
    FIFO#(PixelOut_t)                    f_out   <- mkFIFO;

    //writer
    Reg#(Bool)                          rg_wr_active <- mkReg(False);
    Reg#(UntileGeometry_t#(bx_w, x_w))  rg_wr_geom   <- mkRegU;
    Reg#(UInt#(bx_w))                   rg_wr_bx     <- mkReg(0);
    Reg#(Bool)                          rg_wr_bx_end <- mkReg(False);
    Reg#(Bit#(6))                       rg_wr_idx    <- mkReg(0);
    Reg#(Bit#(1))                       rg_wr_buf    <- mkReg(0);

    //reader
    Reg#(UInt#(x_w)) rg_rd_x    <- mkReg(0);
    Reg#(UInt#(3))   rg_rd_line <- mkReg(0);

    Vector#(2, Reg#(Bool)) rg_busy <- replicateM(mkReg(False));
    RWire#(Bit#(1))        w_set   <- mkRWire;
    RWire#(Bit#(1))        w_clear <- mkRWire;

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_busy;
        for(Integer b = 0; b < 2; b = b + 1) begin
            if(w_set.wget == tagged Valid fromInteger(b))        rg_busy[b] <= True;
            else if(w_clear.wget == tagged Valid fromInteger(b)) rg_busy[b] <= False;
        end
    endrule

    rule r_geometry;
        let f = f_frame.first; f_frame.deq;
        UInt#(13) bw = truncate((f.width + 7) >> 3);
        f_geom.enq(UntileGeometry_t {
            bx_last:   truncate(bw - 1),
            x_last:    truncate(f.width - 1),
            line_last: truncate(f.height - 1)
        });
    endrule

    rule r_frame (!rg_wr_active);
        let g = f_geom.first; f_geom.deq;
        rg_wr_geom   <= g;
        rg_wr_bx     <= 0;
        rg_wr_bx_end <= g.bx_last == 0;
        rg_wr_idx    <= 0;
        rg_wr_active <= True;
    endrule

    rule r_write (rg_wr_active && !rg_busy[rg_wr_buf]);
        let px = f_in.first; f_in.deq;
        i_mem.portA.request.put(BRAMRequest {
            write:           True,
            responseOnWrite: False,
            address:         {rg_wr_buf, rg_wr_idx[5:3], pack(rg_wr_bx), rg_wr_idx[2:0]},
            datain:          px.pixel
        });
        rg_wr_idx <= rg_wr_idx + 1;
        if(rg_wr_idx == 63) begin
            Bool group_end = rg_wr_bx_end;
            rg_wr_bx     <= group_end ? 0 : rg_wr_bx + 1;
            rg_wr_bx_end <= group_end ? rg_wr_geom.bx_last == 0 : rg_wr_bx + 1 == rg_wr_geom.bx_last;
            if(group_end) begin
                f_group.enq(UntileGroup_t {
                    buffer:    rg_wr_buf,
                    line_last: px.last ? rg_wr_geom.line_last : 7,
                    x_last:    rg_wr_geom.x_last,
                    last:      px.last
                });
                w_set.wset(rg_wr_buf);
                if(double_buffer) rg_wr_buf <= ~rg_wr_buf;
                if(px.last) rg_wr_active <= False;
            end
        end
    endrule

    rule r_issue;
        let  g         = f_group.first;
        Bool line_end  = rg_rd_x == g.x_last;
        Bool group_end = line_end && rg_rd_line == g.line_last;

        i_mem.portB.request.put(BRAMRequest {
            write:           False,
            responseOnWrite: False,
            address:         {g.buffer, pack(rg_rd_line), pack(rg_rd_x)},
            datain:          ?
        });
        f_meta.enq(UntileRead_t {
            buffer:     g.buffer,
            group_last: group_end,
            frame_last: group_end && g.last
        });

        rg_rd_x <= line_end ? 0 : rg_rd_x + 1;
        if(line_end) rg_rd_line <= group_end ? 0 : rg_rd_line + 1;
        if(group_end) f_group.deq;
    endrule

    rule r_emit;
        let px <- i_mem.portB.response.get;
        let m = f_meta.first; f_meta.deq;
        f_out.enq(PixelOut_t {
            pixel: px,
            last:  m.frame_last
        });
        //the buffer of a group is free once its last pixel has left the BRAM
        if(m.group_last) w_clear.wset(m.buffer);
    endrule

    interface frame   = toPut(f_frame);
    interface pix_in  = toPut(f_in);
    interface pix_out = toGet(f_out);

endmodule

module mkImageUntilingEngineBypass(ImageUntilingEngine_ifc);

    FIFO#(PixelOut_t) f_px <- mkFIFO;

    interface Put frame;
        method Action put(FrameInfo_t f) = noAction;
    endinterface

    interface pix_in  = toPut(f_px);
    interface pix_out = toGet(f_px);

endmodule

endpackage
