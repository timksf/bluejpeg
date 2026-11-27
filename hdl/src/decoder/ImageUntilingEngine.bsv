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
import McuMerger :: *;

interface ImageUntilingEngine_ifc;
    interface Put#(FrameInfo_t)  frame;
    interface Put#(CompSample_t) sample;
    interface Get#(PixelOut_t)   pix_out;
endinterface

//geometry of one frame, derived once when the frame starts
typedef struct {
    UInt#(bx_w) mx_last;
    UInt#(2)    step;
    Bool        sub444;
    Bool        sub420;
    Bool        gray;
    UInt#(x_w)  x_last;
    UInt#(4)    line_last;
} UntileGeometry_t#(numeric type bx_w, numeric type x_w) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(1)    buffer;
    UInt#(4)   line_last;
    UInt#(x_w) x_last;
    Bool       last;
    Bool       sub444;
    Bool       sub420;
    Bool       gray;
} UntileGroup_t#(numeric type x_w) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(1) buffer;
    Bool    group_last;
    Bool    frame_last;
    Bool    gray;
} UntileRead_t deriving(Bits, Eq, FShow);

/*
 * Output stage, the inverse of the encoder's mkImageTilingEngine. With
 * enable, the component samples of each block are collected per MCU row (a
 * group of 8 lines, 16 for 4:2:0) in planar line buffers and read back in
 * raster order, one pixel per cycle, with the chroma upsampled and the frame
 * cropped. Without enable, the MCU merger joins 4:4:4 samples into pixels in
 * block order like the encoder expects them without its tiler, and the frame
 * geometry is dropped.
 */
module mkImageUntilingEngine#(
    NumProxy_t#(max_img_width) p,
    Bool                       enable,
    Bool                       double_buffer,
    Bool                       en_chroma,
    ChromaSub_t                max_sub
)(ImageUntilingEngine_ifc)
    provisos(
        NumAlias#(TLog#(TDiv#(TAdd#(max_img_width, 7), 8)), bx_w),
        Add#(bx_w, a__, 13),
        Add#(2, c__, bx_w)
    );
    ImageUntilingEngine_ifc ifc;
    if(enable)
        ifc <- mkImageUntilingEngineActive(p, double_buffer, en_chroma, max_sub);
    else
        ifc <- mkImageUntilingEngineBypass(en_chroma);
    return ifc;
endmodule

/*
 * Planar line buffers, an 8-bit luma plane and a 16-bit chroma plane that
 * holds Cb and Cr side by side and writes them with byte enables. A plane
 * line is as wide as the widest frame, the luma plane holds 16 lines when
 * 4:2:0 is supported and 8 otherwise, the chroma plane always 8, which 4:4:4
 * fills completely and 4:2:2 and 4:2:0 to half its width.
 *
 * Each sample is written as it arrives, so the write side keeps the rate of
 * the IDCT. Pixel p of a block has row p / 8 and column p % 8, and the MCU
 * column mx starts at the 8-pixel column base = mx * (1 or 2). A luma block
 * at sub {row, column} lands at line 8 * sub[1] + p / 8 and 8-pixel column
 * base | sub[0], a chroma block at line p / 8 and column base (4:4:4) or
 * base / 2. Raster reads take luma (x, line) and chroma (x, line) for 4:4:4,
 * (x / 2, line) for 4:2:2 and (x / 2, line / 2) for 4:2:0, so subsampled
 * chroma is replicated. Grayscale frames read no chroma and output 128.
 *
 * The writer fills one group, hands its descriptor to the reader and marks
 * the buffer busy until the reader has consumed its last pixel. With
 * double_buffer the writer continues into the second buffer meanwhile. Read
 * metadata travels in a FIFO next to the BRAM responses, which the BRAM
 * servers throttle by credit, and the BRAM output registers are enabled.
 * Frame geometry is derived once per frame, so the streaming rules only
 * compare counters with registers.
 */
module mkImageUntilingEngineActive#(
    NumProxy_t#(max_img_width) _p,
    Bool                       double_buffer,
    Bool                       en_chroma,
    ChromaSub_t                max_sub
)(ImageUntilingEngine_ifc)
    provisos(
        NumAlias#(TLog#(TDiv#(TAdd#(max_img_width, 7), 8)), bx_w),
        NumAlias#(TAdd#(bx_w, 3), x_w),
        NumAlias#(TAdd#(x_w, 5), ya_w),
        NumAlias#(TAdd#(x_w, 4), ca_w),
        Add#(bx_w, a__, 13),
        Add#(x_w, b__, 16),
        Add#(2, c__, bx_w)
    );

    Integer n_buffers = double_buffer ? 2 : 1;
    Bool    en_420    = en_chroma && max_sub == Sub420;
    Integer y_lines   = en_420 ? 16 : 8;

    BRAM_Configure y_cfg = defaultValue;
    y_cfg.memorySize   = n_buffers * y_lines * (2 ** valueOf(x_w));
    y_cfg.latency      = 2;
    y_cfg.outFIFODepth = 4;

    BRAM_Configure c_cfg = defaultValue;
    c_cfg.memorySize   = en_chroma ? n_buffers * 8 * (2 ** valueOf(x_w)) : 2;
    c_cfg.latency      = 2;
    c_cfg.outFIFODepth = 4;

    BRAM2Port#(Bit#(ya_w), UInt#(8))      i_y <- mkBRAM2Server(y_cfg);
    BRAM2PortBE#(Bit#(ca_w), Bit#(16), 2) i_c <- mkBRAM2ServerBE(c_cfg);

    FIFO#(FrameInfo_t)                   f_frame <- mkFIFO;
    FIFO#(UntileGeometry_t#(bx_w, x_w))  f_geom  <- mkFIFO;
    FIFO#(CompSample_t)                  f_in    <- mkFIFO;
    FIFO#(UntileGroup_t#(x_w))           f_group <- mkSizedFIFO(2);
    FIFO#(UntileRead_t)                  f_meta  <- mkSizedFIFO(5);
    FIFO#(PixelOut_t)                    f_out   <- mkFIFO;

    //writer
    Reg#(Bool)                          rg_wr_active <- mkReg(False);
    Reg#(UntileGeometry_t#(bx_w, x_w))  rg_wr_geom   <- mkRegU;
    Reg#(UInt#(bx_w))                   rg_wr_mx     <- mkReg(0);
    Reg#(UInt#(bx_w))                   rg_wr_base   <- mkReg(0);
    Reg#(Bool)                          rg_wr_mx_end <- mkReg(False);
    Reg#(Bit#(6))                       rg_wr_idx    <- mkReg(0);
    Reg#(Bit#(1))                       rg_wr_buf    <- mkReg(0);

    //reader
    Reg#(UInt#(x_w)) rg_rd_x    <- mkReg(0);
    Reg#(UInt#(4))   rg_rd_line <- mkReg(0);

    Vector#(2, Reg#(Bool)) rg_busy <- replicateM(mkReg(False));
    RWire#(Bit#(1))        w_set   <- mkRWire;
    RWire#(Bit#(1))        w_clear <- mkRWire;

    //plane rows {buffer, line} packed so that the used addresses form one range from zero
    function Bit#(5) y_rows(Bit#(1) b, UInt#(4) line);
        Bit#(4) l = pack(line);
        Bit#(5) r = {1'b0, l};
        if(double_buffer) r = en_420 ? {b, l} : {1'b0, b, l[2:0]};
        return r;
    endfunction

    function Bit#(4) c_rows(Bit#(1) b, UInt#(3) line) = double_buffer ? {b, pack(line)} : {1'b0, pack(line)};

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_busy;
        for(Integer b = 0; b < 2; b = b + 1) begin
            if(w_set.wget == tagged Valid fromInteger(b))        rg_busy[b] <= True;
            else if(w_clear.wget == tagged Valid fromInteger(b)) rg_busy[b] <= False;
        end
    endrule

    rule r_geometry;
        let       f      = f_frame.first; f_frame.deq;
        Bool      sub444 = f.sub == Sub444;
        Bool      sub420 = f.sub == Sub420;
        UInt#(13) mw     = truncate(sub444 ? (f.width + 7) >> 3 : (f.width + 15) >> 4);
        UInt#(16) hm1    = f.height - 1;
        f_geom.enq(UntileGeometry_t {
            mx_last:   truncate(mw - 1),
            step:      sub444 ? 1 : 2,
            sub444:    sub444,
            sub420:    sub420,
            gray:      f.ncomp == 1,
            x_last:    truncate(f.width - 1),
            line_last: sub420 ? truncate(hm1) : extend(UInt#(3)'(truncate(hm1)))
        });
    endrule

    rule r_frame (!rg_wr_active);
        let g = f_geom.first; f_geom.deq;
        rg_wr_geom   <= g;
        rg_wr_mx     <= 0;
        rg_wr_base   <= 0;
        rg_wr_mx_end <= g.mx_last == 0;
        rg_wr_idx    <= 0;
        rg_wr_active <= True;
    endrule

    rule r_write (rg_wr_active && !rg_busy[rg_wr_buf]);
        let     s   = f_in.first; f_in.deq;
        let     t   = s.tag;
        Bit#(3) row = rg_wr_idx[5:3];
        Bit#(3) col = rg_wr_idx[2:0];

        if(t.comp == 0) begin
            UInt#(bx_w) bx = rg_wr_base | (t.sub[0] == 1 ? 1 : 0);
            i_y.portA.request.put(BRAMRequest {
                write:           True,
                responseOnWrite: False,
                address:         {y_rows(rg_wr_buf, unpack({t.sub[1], row})), pack(bx), col},
                datain:          s.sample
            });
        end else if(en_chroma) begin
            UInt#(bx_w) bx = rg_wr_geom.sub444 ? rg_wr_base : rg_wr_base >> 1;
            i_c.portA.request.put(BRAMRequestBE {
                writeen:         t.comp == 1 ? 2'b01 : 2'b10,
                responseOnWrite: False,
                address:         {c_rows(rg_wr_buf, unpack(row)), pack(bx), col},
                datain:          {pack(s.sample), pack(s.sample)}
            });
        end

        rg_wr_idx <= rg_wr_idx + 1;
        if(rg_wr_idx == 63 && t.mcu_end) begin
            Bool group_end = rg_wr_mx_end;
            rg_wr_mx     <= group_end ? 0 : rg_wr_mx + 1;
            rg_wr_base   <= group_end ? 0 : rg_wr_base + extend(rg_wr_geom.step);
            rg_wr_mx_end <= group_end ? rg_wr_geom.mx_last == 0 : rg_wr_mx + 1 == rg_wr_geom.mx_last;
            if(group_end) begin
                f_group.enq(UntileGroup_t {
                    buffer:    rg_wr_buf,
                    line_last: t.last ? rg_wr_geom.line_last : (rg_wr_geom.sub420 ? 15 : 7),
                    x_last:    rg_wr_geom.x_last,
                    last:      t.last,
                    sub444:    rg_wr_geom.sub444,
                    sub420:    rg_wr_geom.sub420,
                    gray:      rg_wr_geom.gray
                });
                w_set.wset(rg_wr_buf);
                if(double_buffer) rg_wr_buf <= ~rg_wr_buf;
                if(t.last) rg_wr_active <= False;
            end
        end
    endrule

    rule r_issue;
        let  g         = f_group.first;
        Bool line_end  = rg_rd_x == g.x_last;
        Bool group_end = line_end && rg_rd_line == g.line_last;

        i_y.portB.request.put(BRAMRequest {
            write:           False,
            responseOnWrite: False,
            address:         {y_rows(g.buffer, rg_rd_line), pack(rg_rd_x)},
            datain:          ?
        });
        if(en_chroma && !g.gray) begin
            UInt#(3)   cl = truncate(g.sub420 ? rg_rd_line >> 1 : rg_rd_line);
            UInt#(x_w) cx = g.sub444 ? rg_rd_x : rg_rd_x >> 1;
            i_c.portB.request.put(BRAMRequestBE {
                writeen:         0,
                responseOnWrite: False,
                address:         {c_rows(g.buffer, cl), pack(cx)},
                datain:          ?
            });
        end
        f_meta.enq(UntileRead_t {
            buffer:     g.buffer,
            group_last: group_end,
            frame_last: group_end && g.last,
            gray:       g.gray
        });

        rg_rd_x <= line_end ? 0 : rg_rd_x + 1;
        if(line_end) rg_rd_line <= group_end ? 0 : rg_rd_line + 1;
        if(group_end) f_group.deq;
    endrule

    rule r_emit;
        let      y  <- i_y.portB.response.get;
        let      m  = f_meta.first; f_meta.deq;
        UInt#(8) cb = 128;
        UInt#(8) cr = 128;
        if(en_chroma && !m.gray) begin
            let c <- i_c.portB.response.get;
            cb = unpack(c[7:0]);
            cr = unpack(c[15:8]);
        end
        f_out.enq(PixelOut_t {
            pixel: YCbCr_t {
                y:  y,
                cb: cb,
                cr: cr
            },
            last:  m.frame_last
        });
        //the buffer of a group is free once its last pixel has left the BRAM
        if(m.group_last) w_clear.wset(m.buffer);
    endrule

    interface frame   = toPut(f_frame);
    interface sample  = toPut(f_in);
    interface pix_out = toGet(f_out);

endmodule

//block-order output, the merger joins Y, Cb and Cr samples into pixels
module mkImageUntilingEngineBypass#(Bool en_chroma)(ImageUntilingEngine_ifc);

    McuMerger_ifc i_merger <- mkMcuMerger(en_chroma);

    interface Put frame;
        method Action put(FrameInfo_t f) = noAction;
    endinterface

    interface sample  = i_merger.comp_sample;
    interface pix_out = i_merger.pixel;

endmodule

endpackage
