package BlueJPEG;

import FIFO :: *;
import FIFOF :: *;
import GetPut :: *;
import Connectable :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;
import DefaultValue :: *;
import ModuleCollect :: *;

import BlueAXI :: *;
import BlueCSR :: *;

import Types :: *;
import PrintUtil :: *;
import ImageTilingEngine :: *;
import ChannelSplitter :: *;
import YBlockReorder :: *;
import ChromaSubsampler :: *;
import ChromaBlockReorder :: *;
import DUDispatcher :: *;
import DUProc :: *;
import RLE :: *;
import HuffEncoder :: *;
import JPEGBitstream :: *;
import JPEGFramewriter :: *;
import TableStorage :: *;
import BlueJPEGRegs :: *;

// ================================================================
// Top-level interface
// ================================================================

interface BlueJPEG_ifc;
    (*prefix="S_AXIS"*)
    interface AXI4_Stream_Rd_Fab#(24, 0) s_axis;
    (*prefix="M_AXIS"*)
    interface AXI4_Stream_Wr_Fab#(8, 0) m_axis;

    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_axi_cfg_rd;
    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_axi_cfg_wr;
endinterface

typedef struct {
    Clock slow_clock;
    Reset slow_reset;
    NumProxy#(max_img_width)    _prx_miw;
    NumProxy#(dct_scale)        _prx_dsc;
    NumProxy#(quant_scale)      _prx_qsc;
    NumProxy#(datapath_width)   _prx_dpw;
    Bool en_tiler;
    Bool double_buffer_tiler;
    Bool en_chroma;
} BlueJPEGCfg_t#(
    numeric type max_img_width,
    numeric type dct_scale,
    numeric type quant_scale,
    numeric type datapath_width
);

typedef enum { S_IDLE, S_CONFIGURE, S_RUNNING, S_FLUSH, S_DONE } FrameState_t deriving(Eq, Bits, FShow);

// ================================================================
// Module
// ================================================================

module [Module] mkBlueJPEG#(BlueJPEGCfg_t#(
        max_imw,
        dct_scale,
        quant_scale,
        dpw
    ) cfg)(BlueJPEG_ifc) provisos(
        // -- quant_scale fits in 32 bits (mkTableStorage, mkDUProc via mkQuantize_RT)
        Add#(a__, quant_scale, 32),

        // -- mkImageTilingEngine: line-width counter fits in BRAM address width (always true)
        Add#(c__, TLog#(max_imw), TLog#(TMul#(max_imw, 8))),

        // -- mkImageTilingEngine: image-width counter fits in 13-bit configure argument
        Add#(e__, TLog#(max_imw), 13),

        // -- mkImageTilingEngine: block-column index width fits in BRAM address width
        Add#(f__, TLog#(TDiv#(TLog#(max_imw), 8)), TLog#(TMul#(max_imw, 8))),

        // -- mkYBlockReorder: max_blk_cols = max_imw / 64 (8×8 blocks across image width).
        //    BRAM stores max_blk_cols × 64 Y pixels; address width = ceil(log2(that)).
        //    Supports non-power-of-2 max widths (e.g. 2560).
        Div#(max_imw, 64, max_blk_cols),
        NumAlias#(bram_addr_w, TLog#(TMul#(max_blk_cols, 64))),
        Add#(g__, bram_addr_w, 32),

        // -- mkChromaBlockReorder: bram with capacity to store 4x4 downsampled blocks for entire 
        //    image width. Address width of 32 has to fit (which it definitely will)
        Add#(b__, TLog#(TMul#(max_blk_cols, 16)), 32),

        // -- mkHuffEncoder:
        //dpw >= 1
        //dpw <= 32
        //flog2
        //truncate in calc_magnitude
        Add#(1, d__, dpw),
        Add#(h__, dpw, 32),
        Add#(dpw, i__, TExp#(TLog#(dpw))),
        Add#(4, j__, TLog#(dpw)),

        Add#(k__, 8, dpw)
    );

    function print_s = print_mod_pre_color_t_s;

    let fast_clock <- exposeCurrentClock;
    let fast_reset <- exposeCurrentReset;

    let du_proc_cfg = DUProcCfg {
        slow_clock       : cfg.slow_clock,
        slow_reset       : cfg.slow_reset,
        buffer_in        : False,
        _dct_scale       : cfg._prx_dsc,
        scale_in_dct     : False,
        transpose_in_dct : False,
        _q_scale         : cfg._prx_qsc,
        debug            : False,
        dct_safe_arith   : True
    };

    NumProxy#(max_blk_cols) _prx_mbc = ?;

    // ---- AXI-Lite config ----

    BlueCSRAccess_ifc#(32, 32, BlueJPEGCfg_ifc) csrs <- create_blue_csr(blue_jpeg_csrs, False);

    RegMapDoc_t#(32) doc <- doc_blue_csr(blue_jpeg_csrs);
    messageM(doc.reg_defs);

    //wrap csrs into axi4l slave
    let axi_csrs <- mkBlueCSRAXI4LiteAdapter(csrs.external, 1, 1);

    // ---- sub-module instantiation ----
    TableStorage_ifc#(quant_scale)          tables      <- mkTableStorage(cfg._prx_qsc, True);

    AXI4_Stream_Rd#(24, 0)                  axis_rd     <- mkAXI4_Stream_Rd(1);
    AXI4_Stream_Wr#(8, 0)                   axis_wr     <- mkAXI4_Stream_Wr(1);

    ImageTilingEngine_ifc#(YCbCr_t, 8, 8)   img_tiler = ?;
    if(cfg.en_tiler) begin
        img_tiler   <- mkImageTilingEngine(cfg._prx_miw, cfg.double_buffer_tiler);
    end
    ChannelSplitter_ifc                     ch_splt     <- mkChannelSplitter;
    YBlockReorder_ifc                       y_reord     <- mkYBlockReorder(_prx_mbc, False);

    NumProxy#(8) _prx_bw = ?;

    ChromaSubsampler_ifc                    subs_cb     = ?;
    ChromaSubsampler_ifc                    subs_cr     = ?;
    ChromaBlockReorder_ifc                  cr_reord_cb = ?;
    ChromaBlockReorder_ifc                  cr_reord_cr = ?;
    DUDispatcher_ifc                        du_disp     = ?;
    if(cfg.en_chroma) begin
        subs_cb     <- mkChromaSubsampler(_prx_bw);
        subs_cr     <- mkChromaSubsampler(_prx_bw);
        cr_reord_cb <- mkChromaBlockReorder(_prx_mbc);
        cr_reord_cr <- mkChromaBlockReorder(_prx_mbc);
        du_disp     <- mkDUDispatcher;
    end

    FIFO#(UInt#(8))                         f_du_pixels <- mkFIFO;

    DUProc_t#(dpw)                          du_proc   <- mkDUProc(du_proc_cfg);

    RLE_ifc#(dpw)                           rle       <- mkRLE();
    HuffEncoder_ifc#(dpw)                   huff      <- mkHuffEncoder();
    JPEGBitstream_ifc                       stuffer   <- mkJPEGBitstream(False);

    JPEGFramewriter_ifc                     fwriter   <- mkJPEGFramewriter(cfg.en_chroma);

    // ---- Table Client <-> Server connections ----

    mkConnection(du_proc.qtable,    tables.quant_scaled);
    mkConnection(huff.huff_dc,      tables.huff_code_dc_server);
    mkConnection(huff.huff_ac,      tables.huff_code_ac_server);
    mkConnection(fwriter.quant_raw, tables.quant_raw);
    mkConnection(fwriter.huff_bits, tables.huff_bits_server);
    mkConnection(fwriter.huff_val,  tables.huff_val_server);

    // ---- Data Path Wiring ----

    if(cfg.en_tiler) begin
        mkConnection(img_tiler.block_out, ch_splt.pix);     //tiler blocks -> channel splitter
    end
    if(cfg.en_chroma) begin
        mkConnection(ch_splt.y, y_reord.pixel_in);             //Y -> block reorder
    end
    mkConnection(ch_splt.cb, subs_cb.pixel_in);            //Cb -> chroma path (or sink in grayscale)
    mkConnection(ch_splt.cr, subs_cr.pixel_in);            //Cr -> chroma path (or sink in grayscale)

    if(cfg.en_chroma) begin
        //64 element deep FIFOs absorb the skew between luma and chroma scheduling.
        FIFO#(UInt#(8)) f_cb_du_buf <- mkSizedFIFO(64);
        FIFO#(UInt#(8)) f_cr_du_buf <- mkSizedFIFO(64);

        mkConnection(subs_cb.pixel_out, cr_reord_cb.pixel_in);   //subsampled Cb -> chroma reorder
        mkConnection(subs_cr.pixel_out, cr_reord_cr.pixel_in);   //subsampled Cr -> chroma reorder

        mkConnection(y_reord.pixel_out, du_disp.y);              //reordered Y -> dispatcher
        mkConnection(cr_reord_cb.pixel_out, toPut(f_cb_du_buf)); //reordered Cb -> chroma DU buffer
        mkConnection(cr_reord_cr.pixel_out, toPut(f_cr_du_buf)); //reordered Cr -> chroma DU buffer
        mkConnection(toGet(f_cb_du_buf), du_disp.cb);            //chroma DU buffer -> dispatcher
        mkConnection(toGet(f_cr_du_buf), du_disp.cr);            //chroma DU buffer -> dispatcher
        mkConnection(du_disp.pix, toPut(f_du_pixels));           //selected DU stream -> common DU FIFO
    end else begin
        mkConnection(ch_splt.y, toPut(f_du_pixels));
    end

    // DU processing pipeline (Server chain)
    // dispatcher outputs UInt#(8), DUProc expects Int#(dpw) - convert
    // (pixel dispatch is handled by r_disp_to_duproc below, which also tracks DU boundaries)
    mkConnection(du_proc.data.response, rle.data.request);
    mkConnection(rle.data.response,     huff.data.request);
    mkConnection(huff.data.response,    stuffer.data.request);

    // ---- control state ----

    Reg#(FrameState_t)          rg_state    <- mkReg(S_IDLE);
    Reg#(SubsamplingMode_t)     rg_mode     <- mkRegU;
    Reg#(Bit#(16))              rg_width    <- mkRegU;
    Reg#(Bit#(16))              rg_height   <- mkRegU;

    // DU counting: tracks phase through interleaved MCU scan
    Reg#(Bit#(16))              rg_mcu_w    <- mkRegU;
    Reg#(Bit#(16))              rg_mcu_h    <- mkRegU;
    Reg#(Bit#(16))              rg_mcu_x    <- mkReg(0);
    Reg#(Bit#(16))              rg_mcu_y    <- mkReg(0);

    // ---- table writes from AXI-Lite ----

    rule r_table_write (rg_state == S_IDLE);
        let cmd <- csrs.internal.table_write.get();
        tables.write_table(cmd.table_type, cmd.addr, cmd.data);
    endrule

    // ---- codegen trigger ----

    rule r_codegen_trigger (rg_state == S_IDLE && csrs.internal.codegen_trig() && !tables.codegen_busy());
        tables.generate_codes(csrs.internal.codegen_type());
        csrs.internal.clear_cg_trig();
    endrule

    // ---- status feedback ----

    rule r_update_status;
        csrs.internal.table_sts(tables.ready(), tables.codegen_busy());
    endrule

    // ---- AXIS input -> tiler ----

    if(cfg.en_tiler) begin
        rule r_axis_to_tiler (rg_state == S_RUNNING);
            csrs.internal.perf_pixels.tick_up(); //count ingested pixels
            let pkg <- axis_rd.pkg.get();
            YCbCr_t pix = unpack(pkg.data);
            img_tiler.line_in.put(pix);
        endrule
    end else begin
        rule r_axis_to_chsplt;
            csrs.internal.perf_pixels.tick_up();
            let pkg <- axis_rd.pkg.get();
            YCbCr_t pix = unpack(pkg.data);
            ch_splt.pix.put(pix);
        endrule
    end

    // ---- scan data bridge: stuffer -> framewriter ----

    rule r_scan_bridge (rg_state == S_RUNNING || rg_state == S_FLUSH);
        let b <- stuffer.data.response.get();
        fwriter.scan_data.put(tagged Valid b);
    endrule

    rule r_scan_end (rg_state == S_FLUSH && stuffer.scan_done());
        fwriter.scan_data.put(tagged Invalid);
        rg_state <= S_DONE;
    endrule

    // ---- framewriter output -> AXI output ----

    rule r_byte_out;
        match {.b, .last_byte} <- fwriter.byte_out.get();
        AXI4_Stream_Pkg#(8, 0) pkg = AXI4_Stream_Pkg {
            data : b,
            user : 0,
            keep : 1,
            dest : 0,
            last : last_byte,
            id   : ?
        };
        axis_wr.pkg.put(pkg);
    endrule

    // ---- DU mode / last tracking ----

    function UInt#(3) dus_per_mcu(SubsamplingMode_t m);
        case (m)
            YCBCR_444: return 3;
            YCBCR_422: return 4;
            YCBCR_420: return 6;
        endcase
    endfunction

    function UInt#(3) y_per_mcu(SubsamplingMode_t m);
        case (m)
            YCBCR_444: return 1;
            YCBCR_422: return 2;
            YCBCR_420: return 4;
        endcase
    endfunction

    Reg#(UInt#(3)) rg_mcu_phase <- mkReg(0);
    Reg#(Bit#(6))  rg_du_pix    <- mkReg(0);  //pixel index within current DU (0-63)

    // Transfer pixels from the configured DU source to DUProc.
    // In grayscale mode, f_du_pixels carries reordered luma directly.
    // In color mode, it carries the interleaved dispatcher output.
    rule r_disp_to_duproc (rg_state == S_RUNNING);
        let p = f_du_pixels.first;
        f_du_pixels.deq;
        du_proc.data.request.put(unpack(extend(pack(p))));

        let n_du = cfg.en_chroma ? dus_per_mcu(rg_mode) : fromInteger(1);
        Bool end_of_mcu = !cfg.en_chroma || (rg_mcu_phase == n_du - 1);
        Bool is_last = (end_of_mcu && rg_mcu_x == rg_mcu_w-1 && rg_mcu_y == rg_mcu_h-1);

        if(rg_du_pix == 0) begin
            PixType_t pt = Luma;
            Bit#(2) comp_id = 0;

            if(cfg.en_chroma) begin
                let n_y = y_per_mcu(rg_mode);
                pt = (rg_mcu_phase < n_y) ? Luma : Chroma;
                comp_id =
                    (rg_mcu_phase < n_y) ?        0 :
                    (rg_mcu_phase == n_du - 2) ?  1 : 2;
            end

            du_proc.du_mode.put(pt);
            rle.du_comp.put(comp_id);
            huff.du_meta.put(HuffDUMeta_t { mode: pt, is_last: is_last });
        end

        if(rg_du_pix == 63) begin
            rg_du_pix <= 0;

            if(end_of_mcu)
                rg_mcu_phase <= 0;
            else
                rg_mcu_phase <= rg_mcu_phase + 1;

            if(end_of_mcu) begin
                if(rg_mcu_x == rg_mcu_w-1) begin
                    rg_mcu_x <= 0;
                    if(rg_mcu_y == rg_mcu_h-1)
                        rg_mcu_y <= 0;
                    else
                        rg_mcu_y <= rg_mcu_y + 1;
                end else begin
                    rg_mcu_x <= rg_mcu_x + 1;
                end
            end

            if(is_last)
                rg_state <= S_FLUSH;
        end else
            rg_du_pix <= rg_du_pix + 1;
    endrule

    // ---- start handling (driven by CTRL register) ----

    rule r_start (rg_state == S_IDLE && csrs.internal.start() && tables.ready() && !tables.codegen_busy());
        let cfg_valid = True;

        let width  = csrs.internal.img_width();
        let height = csrs.internal.img_height();
        let mode   = csrs.internal.subsampling();
        let eff_mode = cfg.en_chroma ? mode : YCBCR_444;

        if(!cfg.en_chroma && mode != YCBCR_444)
            cfg_valid = False;

        rg_width  <= width;
        rg_height <= height;
        rg_mode   <= eff_mode;

        //safe division
        Bit#(16) blk_cols = (width  + 7) >> 3;
        Bit#(16) blk_rows = (height + 7) >> 3;

        Bit#(16) mcu_cols = blk_cols;
        Bit#(16) mcu_rows = blk_rows;

        case (eff_mode)
            YCBCR_444: begin mcu_cols = blk_cols;              mcu_rows = blk_rows;              end
            YCBCR_422: begin mcu_cols = (blk_cols + 1) >> 1;   mcu_rows = blk_rows;              end
            YCBCR_420: begin mcu_cols = (blk_cols + 1) >> 1;   mcu_rows = (blk_rows + 1) >> 1;   end
        endcase

        rg_state        <= cfg_valid ? S_RUNNING : S_IDLE;
        rg_mcu_w        <= mcu_cols;
        rg_mcu_h        <= mcu_rows;
        rg_mcu_x        <= 0;
        rg_mcu_y        <= 0;
        rg_mcu_phase    <= 0;
        rg_du_pix       <= 0;

        if(cfg_valid) begin
            if(cfg.en_tiler) begin
                img_tiler.set_img_width(truncate(width));
                img_tiler.start();
            end

            du_disp.set_mode(eff_mode);
            y_reord.configure(eff_mode, truncate(blk_cols));
            subs_cb.configure(eff_mode);
            subs_cr.configure(eff_mode);
            cr_reord_cb.configure(eff_mode, truncate(blk_cols));
            cr_reord_cr.configure(eff_mode, truncate(blk_cols));
            fwriter.configure(width, height, eff_mode);

            fwriter.start();
            csrs.internal.perf_rst();
        end else begin
            csrs.internal.invalid_cfg();
        end
    endrule

    rule rperf (rg_state == S_RUNNING);
        csrs.internal.perf_cycles.tick_up();
    endrule

    // ---- done handling ----

    rule r_done (rg_state == S_DONE && fwriter.done());
        csrs.internal.finish();
        rg_state <= S_IDLE;
    endrule

    // ---- interfaces ----

    interface s_axis       = axis_rd.fab;
    interface m_axis       = axis_wr.fab;
    interface s_axi_cfg_rd = axi_csrs.s_rd;
    interface s_axi_cfg_wr = axi_csrs.s_wr;

endmodule

endpackage
