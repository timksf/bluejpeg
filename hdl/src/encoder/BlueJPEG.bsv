package BlueJPEG;

import FIFO :: *;
import FIFOF :: *;
import Assert :: *;
import GetPut :: *;
import Connectable :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;
import DefaultValue :: *;
import ModuleCollect :: *;
import BlueAXI :: *;
import BlueCSRAXI4LiteAdapter :: *;
import BlueCSRCore :: *;
import BlueCSRExport :: *;

import Types :: *;
import PrintUtil :: *;
import ImageTilingEngine :: *;
import ChannelSplitter :: *;
import DUDispatcher :: *;
import DUProc :: *;
import RLE :: *;
import HuffEncoder :: *;
import JPEGBitstream :: *;
import JPEGFramewriter :: *;
import TableStorage :: *;
import BlueJPEGRegs :: *;

interface BlueJPEG_ifc;
    (*prefix="S_AXIS"*)
    interface AXI4_Stream_Rd_Fab#(24, 0) s_axis;
    (*prefix="M_AXIS"*)
    interface AXI4_Stream_Wr_Fab#(8, 0) m_axis;

    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_axi_cfg_rd;
    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_axi_cfg_wr;

    //level interrupt, high while any enabled IRQP bit is pending
    (* always_ready, result="irq" *)
    method Bool irq;

    //a frame is in progress, from the accepted start request until done
    (* always_ready, result="busy" *)
    method Bool busy;
endinterface

typedef struct {
    Clock                      slow_clock;
    Reset                      slow_reset;
    NumProxy_t#(max_img_width) _prx_miw;
    NumProxy_t#(dct_scale)     _prx_dsc;
    NumProxy_t#(quant_scale)   _prx_qsc;
    NumProxy_t#(pixel_width)   _prx_pixw;
    Bool                       en_tiler;
    Bool                       double_buffer_tiler;
    Bool                       en_chroma;
} BlueJPEGCfg_t#(
    numeric type max_img_width,
    numeric type dct_scale,
    numeric type quant_scale,
    numeric type pixel_width
);

typedef enum { S_IDLE, S_CONFIGURE, S_RUNNING, S_FLUSH, S_DONE } FrameState_t deriving(Bits, Eq, FShow);

module [Module] mkBlueJPEG#(BlueJPEGCfg_t#(
        max_imw,
        dct_scale,
        quant_scale,
        pixel_bits
    ) cfg)(BlueJPEG_ifc)
    provisos(
        //quant_scale fits in 32 bits (mkTableStorage, mkDUProc via mkQuantize_RT)
        Add#(a__, quant_scale, 32),

        //JPEG component samples are 8 bits
        Add#(0, pixel_bits, 8),

        //DCT2D widens centered samples by 7 bits
        NumAlias#(dct_bits, TAdd#(pixel_bits, 7)),

        //mkImageTilingEngine: line-width counter fits in BRAM address width (always true)
        Add#(c__, TLog#(max_imw), TLog#(TMul#(max_imw, 8))),

        //mkImageTilingEngine: image-width counter fits in 13-bit configure argument
        Add#(e__, TLog#(max_imw), 13),

        //mkImageTilingEngine: block-column index width fits in BRAM address width
        Add#(f__, TLog#(TDiv#(TLog#(max_imw), 8)), TLog#(TMul#(max_imw, 8))),

        //mkImageTilingEngine: local addresses and counters fit the dual-port buffer
        Add#(TLog#(max_imw), l__, TLog#(TAdd#(TMul#(max_imw, 8), 1))),
        Add#(TLog#(TMul#(max_imw, 8)), m__, TLog#(TMul#(2, TMul#(max_imw, 8)))),
        Add#(TLog#(TMul#(max_imw, 8)), n__, TLog#(TAdd#(TMul#(max_imw, 8), 1))),

        //mkHuffEncoder:
        //dct_bits >= 1
        //dct_bits <= 32
        //flog2
        //truncate in calc_magnitude
        Add#(1, d__, dct_bits),
        Add#(h__, dct_bits, 32),
        Add#(dct_bits, i__, TExp#(TLog#(dct_bits))),
        Add#(4, j__, TLog#(dct_bits))
    );

    staticAssert(valueOf(dct_scale) > 0,        "BlueJPEG DCT scale must be greater than zero");
    staticAssert(valueOf(quant_scale) > 0,      "BlueJPEG quantization scale must be greater than zero");
    staticAssert(valueOf(quant_scale) <= 32,    "BlueJPEG quantization scale must not exceed 32 bits");
    staticAssert(valueOf(pixel_bits) == 8,      "BlueJPEG pixel width must be 8 bits");

    function print_s = print_mod_pre_color_t_s;

    let fast_clock <- exposeCurrentClock;
    let fast_reset <- exposeCurrentReset;

    let du_proc_cfg = DUProcCfg_t {
        slow_clock       : cfg.slow_clock,
        slow_reset       : cfg.slow_reset,
        buffer_in        : False,
        _dct_scale       : cfg._prx_dsc,
        scale_in_dct     : False,
        transpose_in_dct : False,
        _q_scale         : cfg._prx_qsc,
        debug            : False,
        dct_safe_arith   : False
    };

    //AXI-Lite config

    BlueCSRAccess_ifc#(32, 32, 1, BlueJPEGCfg_ifc) i_csrs     <- create_blue_csr(blue_jpeg_csrs, False);
    BlueCSR_AXI4Lite_ifc#(32, 32, 1)               i_axi_csrs <- mkBlueCSRAXI4LiteAdapter(i_csrs.external, 1, 1);

    //optional documentations generation for CSRs
    RegMapDoc_t#(32) doc <- doc_blue_csr(blue_jpeg_csrs);
    // messageM(doc.reg_defs);

    //submodules
    TableStorage_ifc#(quant_scale) i_tables <- mkTableStorage(cfg._prx_qsc, True);

    AXI4_Stream_Rd#(24, 0) i_axis_rd <- mkAXI4_Stream_Rd(1);
    AXI4_Stream_Wr#(8, 0)  i_axis_wr <- mkAXI4_Stream_Wr(1);

    ImageTilingEngine_ifc#(YCbCr_t, 8, 8) i_img_tiler = ?;
    if(cfg.en_tiler) begin
        i_img_tiler <- mkImageTilingEngine(cfg._prx_miw, cfg.double_buffer_tiler);
    end
    ChannelSplitter_ifc i_ch_splt <- mkChannelSplitter();
    DUDispatcher_ifc    i_du_disp = ?;
    if(cfg.en_chroma) begin
        i_du_disp <- mkDUDispatcher;
    end

    FIFO#(UInt#(8)) f_du_pixels <- mkFIFO;

    DUProc_ifc#(pixel_bits)    i_du_proc <- mkDUProc_Opt(du_proc_cfg);
    RLE_ifc#(dct_bits)         i_rle     <- mkRLE();
    HuffEncoder_ifc#(dct_bits) i_huff    <- mkHuffEncoder();
    JPEGBitstream_ifc          i_stuffer <- mkJPEGBitstream(False);
    JPEGFramewriter_ifc        i_fwriter <- mkJPEGFramewriter(cfg.en_chroma);

    //table client <-> server connections

    mkConnection(i_du_proc.qtable,    i_tables.quant_scaled);
    mkConnection(i_huff.huff_dc,      i_tables.huff_code_dc_server);
    mkConnection(i_huff.huff_ac,      i_tables.huff_code_ac_server);
    mkConnection(i_fwriter.quant_raw, i_tables.quant_raw);
    mkConnection(i_fwriter.huff_bits, i_tables.huff_bits_server);
    mkConnection(i_fwriter.huff_val,  i_tables.huff_val_server);

    //data path wiring

    if(cfg.en_tiler) begin
        mkConnection(i_img_tiler.block_out, i_ch_splt.pix);     //tiler blocks -> channel splitter
    end
    if(cfg.en_chroma) begin
        mkConnection(i_ch_splt.y,     i_du_disp.y);
        mkConnection(i_ch_splt.cb,    i_du_disp.cb);
        mkConnection(i_ch_splt.cr,    i_du_disp.cr);
        mkConnection(i_du_disp.pix,   toPut(f_du_pixels));
    end else begin
        mkConnection(i_ch_splt.y, toPut(f_du_pixels));
        rule r_discard_cb;
            let p <- i_ch_splt.cb.get();
        endrule
        rule r_discard_cr;
            let p <- i_ch_splt.cr.get();
        endrule
    end

    //DU processing pipeline (Server chain)
    //pixel dispatch is handled by r_disp_to_duproc below, which also tracks DU boundaries
    mkConnection(i_du_proc.data.response, i_rle.data.request);
    mkConnection(i_rle.data.response,     i_huff.data.request);
    mkConnection(i_huff.data.response,    i_stuffer.data.request);

    //control state

    Reg#(FrameState_t) rg_state    <- mkReg(S_IDLE);
    Reg#(Bool)         rg_booted   <- mkReg(False); //tables were ready once since reset
    PulseWire          pw_pixel_in <- mkPulseWire;  //a pixel entered the pipeline this cycle

    //DU counting: tracks phase through interleaved MCU scan
    Reg#(Bit#(16)) rg_mcu_w <- mkRegU;
    Reg#(Bit#(16)) rg_mcu_h <- mkRegU;
    Reg#(Bit#(16)) rg_mcu_x <- mkReg(0);
    Reg#(Bit#(16)) rg_mcu_y <- mkReg(0);

    //table writes from AXI-Lite

    rule r_table_write (rg_state == S_IDLE);
        let cmd <- i_csrs.internal.table_write.get();
        i_tables.write_table(cmd.table_type, cmd.addr, cmd.data);
    endrule

    //codegen trigger

    rule r_codegen_trigger (rg_state == S_IDLE && i_csrs.internal.codegen_trig() && !i_tables.codegen_busy());
        i_tables.generate_codes(i_csrs.internal.codegen_type());
        i_csrs.internal.clear_cg_trig();
    endrule

    //status feedback

    rule r_update_status;
        i_csrs.internal.table_sts(i_tables.ready(), i_tables.codegen_busy());
    endrule

    //AXIS input -> tiler

    if(cfg.en_tiler) begin
        rule r_axis_to_tiler (rg_state == S_RUNNING);
            i_csrs.internal.perf_pixels.tick(); //count ingested pixels
            pw_pixel_in.send;
            let pkg <- i_axis_rd.pkg.get();
            YCbCr_t pix = unpack(pkg.data);
            i_img_tiler.line_in.put(pix);
        endrule
    end else begin
        rule r_axis_to_chsplt;
            i_csrs.internal.perf_pixels.tick();
            pw_pixel_in.send;
            let pkg <- i_axis_rd.pkg.get();
            YCbCr_t pix = unpack(pkg.data);
            i_ch_splt.pix.put(pix);
        endrule
    end

    //scan data bridge: stuffer -> framewriter

    //scan_done can rise while the stuffer still holds output bytes, so the bridge drains them before the end marker
    (* descending_urgency = "r_scan_bridge, r_scan_end" *)
    rule r_scan_bridge (rg_state == S_RUNNING || rg_state == S_FLUSH);
        let b <- i_stuffer.data.response.get();
        i_fwriter.scan_data.put(tagged Valid b);
    endrule

    rule r_scan_end (rg_state == S_FLUSH && i_stuffer.scan_done());
        i_fwriter.scan_data.put(tagged Invalid);
        rg_state <= S_DONE;
    endrule

    //framewriter output -> AXI output

    rule r_byte_out;
        match {.b, .last_byte} <- i_fwriter.byte_out.get();
        AXI4_Stream_Pkg#(8, 0) pkg = AXI4_Stream_Pkg {
            data : b,
            user : 0,
            keep : 1,
            dest : 0,
            last : last_byte,
            id   : ?
        };
        i_axis_wr.pkg.put(pkg);
        i_csrs.internal.perf_byteso.tick();
    endrule

    //DU mode / last tracking

    Reg#(UInt#(3)) rg_mcu_phase <- mkReg(0);
    Reg#(Bit#(6))  rg_du_pix    <- mkReg(0); //pixel index within current DU (0-63)

    //transfer pixels from the configured DU source to DUProc
    //in grayscale mode, f_du_pixels carries luma directly
    //in color mode, it carries the interleaved dispatcher output
    rule r_disp_to_duproc (rg_state == S_RUNNING);
        let p = f_du_pixels.first;
        f_du_pixels.deq;
        i_du_proc.data.request.put(p);

        let n_du = cfg.en_chroma ? 3 : fromInteger(1);
        Bool end_of_mcu = !cfg.en_chroma || (rg_mcu_phase == n_du - 1);
        Bool is_last    = (end_of_mcu && rg_mcu_x == rg_mcu_w-1 && rg_mcu_y == rg_mcu_h-1);

        if(rg_du_pix == 0) begin
            PixType_t pt      = Luma;
            Bit#(2)   comp_id = 0;

            if(cfg.en_chroma) begin
                pt = (rg_mcu_phase == 0) ? Luma : Chroma;
                comp_id = truncate(pack(rg_mcu_phase));
            end

            i_du_proc.du_mode.put(pt);
            i_rle.du_comp.put(comp_id);
            i_huff.du_meta.put(HuffDUMeta_t { mode: pt, is_last: is_last });
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

    //start handling (driven by CTRL register)

    //a pending codegen request runs before a start is accepted
    rule r_start (rg_state == S_IDLE && i_csrs.internal.start() && !i_csrs.internal.codegen_trig() && i_tables.ready());
        //consume each request once, including rejected configurations
        i_csrs.internal.clear_start();
        let cfg_valid = True;

        let width  = i_csrs.internal.img_width();
        let height = i_csrs.internal.img_height();

        if(width == 0 || height == 0 || width > fromInteger(valueOf(max_imw)))
            cfg_valid = False;
        if(width[2:0] != 0 || height[2:0] != 0)
            cfg_valid = False;

        //safe division
        Bit#(16) blk_cols = (width  + 7) >> 3;
        Bit#(16) blk_rows = (height + 7) >> 3;

        rg_state        <= cfg_valid ? S_CONFIGURE : S_IDLE;
        rg_mcu_w        <= blk_cols;
        rg_mcu_h        <= blk_rows;
        rg_mcu_x        <= 0;
        rg_mcu_y        <= 0;
        rg_mcu_phase    <= 0;
        rg_du_pix       <= 0;

        if(cfg_valid) begin
            i_csrs.internal.clear_done();
            if(cfg.en_tiler)
                i_img_tiler.set_img_width(truncate(width));

            i_fwriter.configure(width, height);
        end else begin
            i_csrs.internal.invalid_cfg();
        end
    endrule

    //start one cycle after configuration so submodules observe their new registers
    rule r_configure (rg_state == S_CONFIGURE);
        if(cfg.en_tiler)
            i_img_tiler.start();
        //reset DC predictors and scan state before accepting frame pixels
        i_rle.rewind();
        i_huff.rewind();
        i_stuffer.rewind();
        i_fwriter.start();
        i_csrs.internal.perf_rst();
        rg_state <= S_RUNNING;
    endrule

    //frame phases: configure and running, then flush (last DU in the pipeline) and done (framewriter tail)
    (* fire_when_enabled, no_implicit_conditions *)
    rule r_perf;
        if(rg_state == S_RUNNING) i_csrs.internal.perf_cycles.tick();
        if(rg_state == S_RUNNING && !pw_pixel_in) i_csrs.internal.perf_idle.tick();
        if(rg_state == S_FLUSH || rg_state == S_DONE) i_csrs.internal.perf_flush.tick();
        if(rg_state != S_IDLE) i_csrs.internal.perf_frame.tick();
        if(!rg_booted) i_csrs.internal.perf_boot.tick();
    endrule

    rule r_boot_done (!rg_booted && i_tables.ready());
        rg_booted <= True;
    endrule

    //done handling

    rule r_done (rg_state == S_DONE && i_fwriter.done());
        if(cfg.en_tiler)
            i_img_tiler.stop();
        i_csrs.internal.finish();
        rg_state <= S_IDLE;
    endrule

    //interfaces

    interface s_axis       = i_axis_rd.fab;
    interface m_axis       = i_axis_wr.fab;
    interface s_axi_cfg_rd = i_axi_csrs.s_rd;
    interface s_axi_cfg_wr = i_axi_csrs.s_wr;

    method irq             = i_axi_csrs.irqs[0];
    method busy            = rg_state != S_IDLE;

endmodule

endpackage
