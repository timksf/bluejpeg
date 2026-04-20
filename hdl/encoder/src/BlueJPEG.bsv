package BlueJPEG;

import FIFO :: *;
import FIFOF :: *;
import GetPut :: *;
import Connectable :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;
import ModuleCollect :: *;

import BlueAXI :: *;
import PrintUtil :: *;
import Types :: *;
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

// ================================================================
// AXI-Lite register map
// ================================================================

//control / status registers
Integer cfg_ctrl_offs        = 'h00;
Integer cfg_status_offs      = 'h04;
Integer cfg_img_size_offs    = 'h08;
Integer cfg_subsampling_offs = 'h0C;
Integer cfg_codegen_offs     = 'h10;

//control register bit positions
Integer ctrl_start_bit  = 0;
Integer ctrl_done_bit   = 1;
Integer ctrl_error_bit  = 2;

//status register bit positions
Integer sts_ready_bit   = 0;
Integer sts_cg_busy_bit = 1;

//codegen register: [1:0]=HuffTableType, [31]=trigger
Integer cg_trigger_bit  = 31;

//table write address ranges
Integer tbl_range_base          = 'h0100;
Integer tbl_range_end           = 'h2000;

Integer tbl_qluma_raw_base      = 'h0100;  // 64 × 4B
Integer tbl_qchroma_raw_base    = 'h0200;
Integer tbl_qluma_sc_base       = 'h0300;
Integer tbl_qchroma_sc_base     = 'h0400;
Integer tbl_hbits_dc_l_base     = 'h0500;  // 16 × 4B
Integer tbl_hbits_dc_c_base     = 'h0540;
Integer tbl_hbits_ac_l_base     = 'h0580;
Integer tbl_hbits_ac_c_base     = 'h05C0;
Integer tbl_hval_dc_l_base      = 'h1000;  // 256 × 4B
Integer tbl_hval_dc_c_base      = 'h1400;
Integer tbl_hval_ac_l_base      = 'h1800;
Integer tbl_hval_ac_c_base      = 'h1C00;

// ================================================================
// Table write command (FIFO element between config slave and TableStorage)
// ================================================================

typedef struct {
    TableType_t table_type;
    Bit#(8)     addr;
    Bit#(32)    data;
} TableWriteCmd_t deriving(Eq, Bits, FShow);

// ================================================================
// Internal config interface (device-facing side of AXI-Lite slave)
// ================================================================

interface BlueJPEGCfg_ifc;
    method Action finish();
    method Action set_status(Bool tables_ready, Bool codegen_busy);
    method Action clear_codegen_trigger();

    interface ReadOnly#(Bool) start;
    interface ReadOnly#(Bit#(16)) img_width;
    interface ReadOnly#(Bit#(16)) img_height;
    interface ReadOnly#(SubsamplingMode_t) subsampling;
    interface ReadOnly#(Bit#(32)) codegen;

    interface Get#(TableWriteCmd_t) table_write;
endinterface

// ================================================================
// Config module (ConfigCtx)
// ================================================================

module [ConfigCtx#(32, 32)] blueJPEGConfig(BlueJPEGCfg_ifc);

    Reg#(Bit#(32)) rg_ctrl         <- mkReg(0);
    Reg#(Bit#(32)) rg_status       <- mkReg(0);
    Reg#(Bit#(32)) rg_img_size     <- mkReg(0);
    Reg#(Bit#(32)) rg_subsampling  <- mkReg(0);
    Reg#(Bit#(32)) rg_codegen      <- mkReg(0);

    FIFO#(TableWriteCmd_t) f_tbl_wr <- mkFIFO;

    // --- scalar registers ---
    addReg(cfg_ctrl_offs, rg_ctrl);
    addRegRO(cfg_status_offs, rg_status);
    addReg(cfg_img_size_offs, rg_img_size);
    addReg(cfg_subsampling_offs, rg_subsampling);
    addReg(cfg_codegen_offs, rg_codegen);

    // --- table write range (0x0100 – 0x1FFF) ---
    // A single WriteRangeOperator covers the whole table space.
    // The handler decodes the address into (TableType_t, index, data).

    function Bool addr_in(Bit#(32) a, Integer base, Integer count);
        return (a >= fromInteger(base)) && (a < fromInteger(base + count * 4));
    endfunction

    function Action tbl_write_handler(Bit#(32) a, Bit#(32) d, Bit#(4) s);
        action
            TableType_t tt = ?;
            Bit#(8) idx = 0;
            Bool valid = True;

            if (addr_in(a, tbl_qluma_raw_base, 64)) begin
                tt = QLuma;          idx = truncate((a - fromInteger(tbl_qluma_raw_base)) >> 2);
            end else if (addr_in(a, tbl_qchroma_raw_base, 64)) begin
                tt = QChroma;        idx = truncate((a - fromInteger(tbl_qchroma_raw_base)) >> 2);
            end else if (addr_in(a, tbl_qluma_sc_base, 64)) begin
                tt = QLumaScaled;    idx = truncate((a - fromInteger(tbl_qluma_sc_base)) >> 2);
            end else if (addr_in(a, tbl_qchroma_sc_base, 64)) begin
                tt = QChromaScaled;  idx = truncate((a - fromInteger(tbl_qchroma_sc_base)) >> 2);
            end else if (addr_in(a, tbl_hbits_dc_l_base, 16)) begin
                tt = HuffLumaDCBits;   idx = truncate((a - fromInteger(tbl_hbits_dc_l_base)) >> 2);
            end else if (addr_in(a, tbl_hbits_dc_c_base, 16)) begin
                tt = HuffChromaDCBits; idx = truncate((a - fromInteger(tbl_hbits_dc_c_base)) >> 2);
            end else if (addr_in(a, tbl_hbits_ac_l_base, 16)) begin
                tt = HuffLumaACBits;   idx = truncate((a - fromInteger(tbl_hbits_ac_l_base)) >> 2);
            end else if (addr_in(a, tbl_hbits_ac_c_base, 16)) begin
                tt = HuffChromaACBits; idx = truncate((a - fromInteger(tbl_hbits_ac_c_base)) >> 2);
            end else if (addr_in(a, tbl_hval_dc_l_base, 256)) begin
                tt = HuffLumaDCVal;    idx = truncate((a - fromInteger(tbl_hval_dc_l_base)) >> 2);
            end else if (addr_in(a, tbl_hval_dc_c_base, 256)) begin
                tt = HuffChromaDCVal;  idx = truncate((a - fromInteger(tbl_hval_dc_c_base)) >> 2);
            end else if (addr_in(a, tbl_hval_ac_l_base, 256)) begin
                tt = HuffLumaACVal;    idx = truncate((a - fromInteger(tbl_hval_ac_l_base)) >> 2);
            end else if (addr_in(a, tbl_hval_ac_c_base, 256)) begin
                tt = HuffChromaACVal;  idx = truncate((a - fromInteger(tbl_hval_ac_c_base)) >> 2);
            end else
                valid = False;

            if (valid)
                f_tbl_wr.enq(TableWriteCmd_t { table_type: tt, addr: idx, data: d });
        endaction
    endfunction

    addToCollection(tagged WriteRangeOperator WriteRangeOperation {
        offset:  fromInteger(tbl_range_base),
        length:  fromInteger(tbl_range_end - tbl_range_base),
        request: tbl_write_handler
    });

    // --- methods ---

    method Action finish();
        let v = rg_ctrl;
        v[ctrl_start_bit] = 0;
        v[ctrl_done_bit]  = 1;
        rg_ctrl <= v;
    endmethod

    method Action set_status(Bool tables_ready, Bool codegen_busy);
        Bit#(32) v = 0;
        v[sts_ready_bit]   = pack(tables_ready);
        v[sts_cg_busy_bit] = pack(codegen_busy);
        rg_status <= v;
    endmethod

    method Action clear_codegen_trigger();
        rg_codegen <= 0;
    endmethod

    interface ReadOnly start;
        method Bool _read();
            return unpack(rg_ctrl[ctrl_start_bit]);
        endmethod
    endinterface

    interface ReadOnly img_width;
        method Bit#(16) _read();
            return rg_img_size[15:0];
        endmethod
    endinterface

    interface ReadOnly img_height;
        method Bit#(16) _read();
            return rg_img_size[31:16];
        endmethod
    endinterface

    interface ReadOnly subsampling;
        method SubsamplingMode_t _read();
            return unpack(truncate(rg_subsampling));
        endmethod
    endinterface

    interface ReadOnly codegen;
        method Bit#(32) _read();
            return rg_codegen;
        endmethod
    endinterface

    interface table_write = toGet(f_tbl_wr);

endmodule

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
} BlueJPEGCfg_t#(
    numeric type max_img_width,
    numeric type dct_scale,
    numeric type quant_scale,
    numeric type datapath_width
);

typedef enum { S_IDLE, S_CONFIGURE, S_RUNNING, S_FLUSH, S_DONE } FrameState_t
    deriving(Eq, Bits, FShow);

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
        debug            : False
    };

    NumProxy#(max_blk_cols) _prx_mbc = ?;

    // ---- AXI-Lite config ----

    IntExtConfig_ifc#(32, 32, BlueJPEGCfg_ifc) config_ <- axi4LiteConfigFromContext(blueJPEGConfig);

    // ---- sub-module instantiation ----

    TableStorage_ifc#(quant_scale)          tables   <- mkTableStorage(cfg._prx_qsc, True);

    AXI4_Stream_Rd#(24, 0)                  axis_rd  <- mkAXI4_Stream_Rd(1);
    AXI4_Stream_Wr#(8, 0)                   axis_wr  <- mkAXI4_Stream_Wr(1);

    ImageTilingEngine_ifc#(YCbCr_t, 8, 8)   img_tiler <- mkImageTilingEngine(cfg._prx_miw);
    ChannelSplitter_ifc                     ch_splt   <- mkChannelSplitter;

    NumProxy#(8) _prx_bw = ?;

    YBlockReorder_ifc                       y_reord   <- mkYBlockReorder(_prx_mbc, False);
    ChromaSubsampler_ifc                    subs_cb   <- mkChromaSubsampler(_prx_bw);
    ChromaSubsampler_ifc                    subs_cr   <- mkChromaSubsampler(_prx_bw);

    ChromaBlockReorder_ifc                  cr_reord_cb <- mkChromaBlockReorder(_prx_mbc);
    ChromaBlockReorder_ifc                  cr_reord_cr <- mkChromaBlockReorder(_prx_mbc);

    DUDispatcher_ifc                        du_disp   <- mkDUDispatcher;
    DUProc_t#(dpw)                          du_proc   <- mkDUProc(du_proc_cfg);

    RLE_ifc#(dpw)                           rle       <- mkRLE;
    HuffEncoder_ifc#(dpw)                   huff      <- mkHuffEncoder;
    JPEGBitstream_ifc                       stuffer   <- mkJPEGBitstream(False);

    JPEGFramewriter_ifc                     fwriter   <- mkJPEGFramewriter;

    // ---- Table Client <-> Server connections ----

    mkConnection(du_proc.qtable,    tables.quant_scaled);
    mkConnection(huff.huff_dc,      tables.huff_code_dc_server);
    mkConnection(huff.huff_ac,      tables.huff_code_ac_server);
    mkConnection(fwriter.quant_raw, tables.quant_raw);
    mkConnection(fwriter.huff_bits, tables.huff_bits_server);
    mkConnection(fwriter.huff_val,  tables.huff_val_server);

    // ---- Data Path Wiring ----

    mkConnection(img_tiler.block_out, ch_splt.pix);         //tiler blocks -> channel splitter
    mkConnection(ch_splt.y,  y_reord.pixel_in);             //Y -> block reorder
    mkConnection(ch_splt.cb, subs_cb.pixel_in);             //Cb -> chroma subsampler
    mkConnection(ch_splt.cr, subs_cr.pixel_in);             //Cr -> chroma subsampler

    //64 element deep fifos for delayed chroma processing
    //without these buffers the pipeline would stall as the channel splitter could
    //not accept enough pixels to finish luma processing before chroma processing
    //could start
    FIFO#(UInt#(8)) f_cb_du_buf <- mkSizedFIFO(64);
    FIFO#(UInt#(8)) f_cr_du_buf <- mkSizedFIFO(64);

    mkConnection(subs_cb.pixel_out, cr_reord_cb.pixel_in);  //subsampled Cb -> chroma reorder
    mkConnection(subs_cr.pixel_out, cr_reord_cr.pixel_in);  //subsampled Cr -> chroma reorder

    mkConnection(y_reord.pixel_out, du_disp.y);             //reordered Y -> dispatcher
    mkConnection(cr_reord_cb.pixel_out, toPut(f_cb_du_buf)); //reordered Cb -> chroma DU buffer
    mkConnection(cr_reord_cr.pixel_out, toPut(f_cr_du_buf)); //reordered Cr -> chroma DU buffer
    mkConnection(toGet(f_cb_du_buf), du_disp.cb);           //chroma DU buffer -> dispatcher
    mkConnection(toGet(f_cr_du_buf), du_disp.cr);           //chroma DU buffer -> dispatcher

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
    Reg#(UInt#(32))             rg_du_cnt   <- mkReg(0);
    Reg#(UInt#(32))             rg_du_total <- mkRegU;

    // ---- table writes from AXI-Lite ----

    rule r_table_write (rg_state == S_IDLE);
        let cmd <- config_.device_ifc.table_write.get();
        tables.write_table(cmd.table_type, cmd.addr, cmd.data);
    endrule

    // ---- codegen trigger ----

    rule r_codegen_trigger (rg_state == S_IDLE
            && unpack(config_.device_ifc.codegen._read()[cg_trigger_bit])
            && !tables.codegen_busy());
        let cg = config_.device_ifc.codegen._read();
        HuffTableType_t htt = unpack(truncate(cg));
        tables.generate_codes(htt);
        config_.device_ifc.clear_codegen_trigger();
    endrule

    // ---- status feedback ----

    rule r_update_status;
        config_.device_ifc.set_status(tables.ready(), tables.codegen_busy());
    endrule

    // ---- AXI input -> tiler ----

    rule r_axis_to_tiler (rg_state == S_RUNNING);
        let pkg <- axis_rd.pkg.get();
        YCbCr_t pix = unpack(pkg.data);
        img_tiler.line_in.put(pix);
    endrule

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
        let b <- fwriter.byte_out.get();
        AXI4_Stream_Pkg#(8, 0) pkg = AXI4_Stream_Pkg {
            data : b,
            user : 0,
            keep : 1,
            dest : 0,
            last : fwriter.done()
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
    Reg#(Bit#(6))  rg_du_pix    <- mkReg(0);  // pixel index within current DU (0-63)

    // Transfer pixels from dispatcher to DUProc, tracking DU boundaries.
    // DU counting and MCU phase advance happen here (synchronized with data flow).
    // At the start of each DU, per-DU metadata is enqueued to each pipeline stage.
    rule r_disp_to_duproc (rg_state == S_RUNNING);
        let p <- du_disp.pix.get();
        du_proc.data.request.put(unpack(extend(pack(p))));

        if (rg_du_pix == 0) begin
            //compute per-DU metadata at DU start
            let n_y  = y_per_mcu(rg_mode);
            let n_du = dus_per_mcu(rg_mode);
            PixType_t pt = (rg_mcu_phase < n_y) ? Luma : Chroma;

            //component ID for separate DC prediction: 0=Y, 1=Cb, 2=Cr
            Bit#(2) comp_id = (rg_mcu_phase < n_y) ? 0 :
                              (rg_mcu_phase == n_du - 2) ? 1 : 2;

            Bool is_last = (rg_du_cnt == rg_du_total - 1);

            du_proc.du_mode.put(pt);
            rle.du_comp.put(comp_id);
            huff.du_meta.put(HuffDUMeta_t { mode: pt, is_last: is_last });
        end

        if (rg_du_pix == 63) begin
            // end of DU - advance MCU phase and DU count
            rg_du_pix <= 0;
            let n_du = dus_per_mcu(rg_mode);
            if (rg_mcu_phase == n_du - 1)
                rg_mcu_phase <= 0;
            else
                rg_mcu_phase <= rg_mcu_phase + 1;

            rg_du_cnt <= rg_du_cnt + 1;

            if (rg_du_cnt == rg_du_total - 1)
                rg_state <= S_FLUSH;
        end else
            rg_du_pix <= rg_du_pix + 1;
    endrule

    // ---- start handling (driven by CTRL register) ----

    rule r_start (rg_state == S_IDLE && config_.device_ifc.start() && tables.ready() && !tables.codegen_busy());
        let width  = config_.device_ifc.img_width();
        let height = config_.device_ifc.img_height();
        let mode   = config_.device_ifc.subsampling();

        rg_width  <= width;
        rg_height <= height;
        rg_mode   <= mode;

        Bit#(16) blk_cols = (width  + 7) >> 3;
        Bit#(16) blk_rows = (height + 7) >> 3;

        Bit#(16) mcu_cols = blk_cols;
        Bit#(16) mcu_rows = blk_rows;
        case (mode)
            YCBCR_444: begin mcu_cols = blk_cols;              mcu_rows = blk_rows;              end
            YCBCR_422: begin mcu_cols = (blk_cols + 1) >> 1;   mcu_rows = blk_rows;              end
            YCBCR_420: begin mcu_cols = (blk_cols + 1) >> 1;   mcu_rows = (blk_rows + 1) >> 1;   end
        endcase

        UInt#(32) n_mcus = unpack(extend(mcu_cols)) * unpack(extend(mcu_rows));
        rg_du_total <= n_mcus * extend(dus_per_mcu(mode));

        img_tiler.set_img_width(truncate(width));
        du_disp.set_mode(mode);
        y_reord.configure(mode, truncate(blk_cols));
        subs_cb.configure(mode);
        subs_cr.configure(mode);
        cr_reord_cb.configure(mode, truncate(blk_cols));
        cr_reord_cr.configure(mode, truncate(blk_cols));
        fwriter.configure(width, height, mode);

        rg_state     <= S_RUNNING;
        rg_du_cnt    <= 0;
        rg_mcu_phase <= 0;
        rg_du_pix    <= 0;
        img_tiler.start();
        fwriter.start();
    endrule

    // ---- done handling ----

    rule r_done (rg_state == S_DONE && fwriter.done());
        config_.device_ifc.finish();
        rg_state <= S_IDLE;
    endrule

    // ---- interfaces ----

    interface s_axis       = axis_rd.fab;
    interface m_axis       = axis_wr.fab;
    interface s_axi_cfg_rd = config_.bus_ifc.s_rd;
    interface s_axi_cfg_wr = config_.bus_ifc.s_wr;

endmodule

endpackage
