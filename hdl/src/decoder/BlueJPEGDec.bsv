package BlueJPEGDec;

import FIFO :: *;
import Assert :: *;
import Vector :: *;
import GetPut :: *;
import Connectable :: *;
import ClientServer :: *;
import BlueAXI :: *;
import BlueCSRAXI4LiteAdapter :: *;
import BlueCSRCore :: *;

import Types :: *;
import DecoderTypes :: *;
import DecTableStorage :: *;
import JPEGMarkerParser :: *;
import JPEGFrameParser :: *;
import JPEGBitstreamDec :: *;
import HuffDecoder :: *;
import RLD :: *;
import Dequantize :: *;
import DeZigZag :: *;
import IDCT :: *;
import IDCTProc :: *;
import ImageUntilingEngine :: *;
import BlueJPEGDecRegs :: *;

export DecoderTypes :: *;
export BlueJPEGDecRegs :: *;
export BlueJPEGDecCfg_t(..);
export BlueJPEGDec_ifc(..);
export mkBlueJPEGDec;

interface BlueJPEGDec_ifc;
    (* prefix="S_AXIS" *)
    interface AXI4_Stream_Rd_Fab#(8, 0) s_axis;
    (* prefix="M_AXIS" *)
    interface AXI4_Stream_Wr_Fab#(24, 0) m_axis;

    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_axi_cfg_rd;
    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_axi_cfg_wr;

    //level interrupt, high while any enabled IRQP bit is pending
    (* always_ready, result="irq" *)
    method Bool irq;

    //at least one frame is between its scan header and its last pixel
    (* always_ready, result="busy" *)
    method Bool busy;
endinterface

/*
 * Compile-time configuration, the counterpart of BlueJPEGCfg_t.
 *
 *   slow_clock, slow_reset  clock of the IDCT, the main clock divided by eight with aligned edges (or the main clock)
 *   max_img_width           widest frame, sets the untiler line buffer
 *   idct_scale              fraction bits of the IDCT constants, at most 15 for one DSP per multiply
 *   dequant_scale           fraction bits of dequantized data, at most 10 for one DSP per multiply
 *   pixel_width             component sample width, baseline JPEG requires 8
 *   en_untiler              raster output, otherwise pixels leave in block order
 *   double_buffer_untiler   overlap filling one MCU row with emitting the previous one
 *   en_chroma               YCbCr support, otherwise grayscale only with half the table storage
 *   en_huff_lookahead       lookahead tables that decode codes of up to eight bits in two cycles instead of three
 *   max_chroma_sub          most subsampled colour format accepted, 4:2:0 doubles the luma line buffer,
 *                           block-order output (no untiler) supports only 4:4:4
 */
typedef struct {
    Clock                      slow_clock;
    Reset                      slow_reset;
    NumProxy_t#(max_img_width) _prx_miw;
    NumProxy_t#(idct_scale)    _prx_dsc;
    NumProxy_t#(dequant_scale) _prx_qsc;
    NumProxy_t#(pixel_width)   _prx_pixw;
    Bool                       en_untiler;
    Bool                       double_buffer_untiler;
    Bool                       en_chroma;
    Bool                       en_huff_lookahead;
    ChromaSub_t                max_chroma_sub;
} BlueJPEGDecCfg_t#(
    numeric type max_img_width,
    numeric type idct_scale,
    numeric type dequant_scale,
    numeric type pixel_width
);

/*
 * Baseline JPEG decoder, the inverse of the BlueJPEG encoder datapath.
 *
 *   s_axis -> marker parser -> bit reader -> Huffman decoder -> RLD -> dequantizer -> inverse zigzag
 *          -> IDCT processing (gearboxes around the IDCT) -> MCU merger -> untiler -> m_axis
 *
 * The marker parser splits header payloads from the entropy-coded segment.
 * The frame parser programs the table storage and the scan configuration
 * from the header, so no tables need to be written over AXI-Lite. Huffman
 * decoder and dequantizer read the table storage through registered clients,
 * like the encoder's Huffman encoder and quantizer. From the inverse zigzag
 * on, the datapath carries one sample per cycle like the encoder's DU
 * processing, and the IDCT runs in slow_clock between two gearboxes. Each
 * block's component, MCU end and frame end travel in a tag FIFO next to the
 * IDCT and rejoin the samples before the merger.
 * Output pixels are YCbCr with the packing the encoder accepts, and TLAST
 * marks the last pixel of a frame. A frame counts as busy from its accepted
 * scan header until that last pixel.
 *
 * Each frame selects its chroma subsampling in its SOF header, up to
 * max_chroma_sub. The untiler upsamples subsampled chroma by replication.
 *
 * Errors do not stop the decoder. Every error raises an ERR event and the
 * decoder recovers at the frame level. A frame with an unsupported or
 * malformed header is dropped up to the next SOI and produces no pixels. A
 * frame whose entropy-coded data is corrupt or cut short is completed with
 * grey blocks, so it still leaves with its full size and TLAST. Bytes outside
 * frames are ignored, so a stream may start anywhere and carry padding.
 */
module [Module] mkBlueJPEGDec#(BlueJPEGDecCfg_t#(
        max_imw,
        idct_scale,
        dequant_scale,
        pixel_bits
    ) cfg)(BlueJPEGDec_ifc)
    provisos(
        //JPEG baseline component samples are 8 bits
        Add#(0, pixel_bits, 8),

        //first IDCT pass width, see IDCTPass1Int
        NumAlias#(TAdd#(dequant_scale, IDCTPass1Int), w_col),
        NumAlias#(TAdd#(w_col, TSub#(IDCTPass2Int, IDCTPass1Int)), w_row),

        //mkIDCT2D: pass widths and products
        Add#(w_col, a__, w_row),
        Add#(w_col, IDCTCoeffBits#(idct_scale), mul_col),
        Add#(w_row, IDCTCoeffBits#(idct_scale), mul_row),
        Add#(w_col, b__, mul_col),
        Add#(w_row, c__, mul_row),
        Add#(8, d__, w_row),

        //mkDequantize: rounded magnitude fits the first pass
        Add#(e__, TSub#(PrescaleProd#(dequant_scale), PrescaleGuard), w_col),
        Add#(PrescaleGuard, f__, PrescaleProd#(dequant_scale)),

        //mkImageUntilingEngine: block column index fits the MCU counter
        Add#(TLog#(TDiv#(TAdd#(max_imw, 7), 8)), g__, 13),
        Add#(2, h__, TLog#(TDiv#(TAdd#(max_imw, 7), 8)))
    );

    staticAssert(valueOf(pixel_bits) == 8,     "BlueJPEGDec pixel width must be 8 bits");
    staticAssert(valueOf(idct_scale) >= 8,     "BlueJPEGDec IDCT scale below 8 bits loses accuracy");
    staticAssert(valueOf(idct_scale) <= 15,    "BlueJPEGDec IDCT scale above 15 bits needs two DSPs per multiply");
    staticAssert(valueOf(dequant_scale) >= 2,  "BlueJPEGDec dequantization scale must be at least 2 bits");
    staticAssert(valueOf(dequant_scale) <= 10, "BlueJPEGDec dequantization scale above 10 bits needs two DSPs per multiply");
    staticAssert(cfg.en_untiler || cfg.max_chroma_sub == Sub444, "BlueJPEGDec block-order output supports only 4:4:4");

    //grayscale-only builds accept only 4:4:4 geometry
    ChromaSub_t max_sub = cfg.en_chroma ? cfg.max_chroma_sub : Sub444;

    //AXI-Lite config

    //requests, address decode and responses registered, so each is a stage of its own
    BlueCSRCfg_t csr_cfg = BlueCSRCfg_t {
        buffer_in:        True,
        buffer_decode:    True,
        buffer_out:       True,
        default_response: CSR_DECERR
    };

    BlueCSRAccess_ifc#(32, 32, 1, BlueJPEGDecCfg_ifc) i_csrs     <- create_blue_csr_cfg(blue_jpeg_dec_csrs, csr_cfg);
    BlueCSR_AXI4Lite_ifc#(32, 32, 1)                  i_axi_csrs <- mkBlueCSRAXI4LiteAdapter(i_csrs.external, 1, 1);

    //submodules

    AXI4_Stream_Rd#(8, 0)  i_axis_rd <- mkAXI4_Stream_Rd(1);
    AXI4_Stream_Wr#(24, 0) i_axis_wr <- mkAXI4_Stream_Wr(1);

    Integer max_width = cfg.en_untiler ? valueOf(max_imw) : 0;

    DecTableStorage_ifc     i_tables  <- mkDecTableStorage(cfg.en_chroma, cfg.en_huff_lookahead);
    JPEGMarkerParser_ifc    i_markers <- mkJPEGMarkerParser;
    JPEGFrameParser_ifc     i_frames  <- mkJPEGFrameParser(i_tables, cfg.en_chroma, max_sub, max_width);
    JPEGBitstreamDec_ifc    i_bits    <- mkJPEGBitstreamDec;
    HuffDecoder_ifc         i_huff    <- mkHuffDecoder(i_bits, i_tables.huff_limits, i_tables.huff_look, i_tables.huff_busy, cfg.en_huff_lookahead);
    RLD_ifc                 i_rld     <- mkRLD;
    Dequantize_ifc#(w_col)  i_dequant <- mkDequantize(cfg._prx_qsc);
    DeZigZag_ifc#(w_col)    i_dezz    <- mkDeZigZag;
    ImageUntilingEngine_ifc i_untiler <- mkImageUntilingEngine(cfg._prx_miw, cfg.en_untiler, cfg.double_buffer_untiler, cfg.en_chroma, max_sub);

    IDCTProcCfg_t#(idct_scale, dequant_scale) idct_cfg = IDCTProcCfg_t {
        slow_clock:     cfg.slow_clock,
        slow_reset:     cfg.slow_reset,
        _idct_scale:    cfg._prx_dsc,
        _dequant_scale: cfg._prx_qsc
    };
    IDCTProc_ifc#(w_col) i_idct <- mkIDCTProc(idct_cfg);

    //table client <-> server connections

    mkConnection(i_huff.huff_val, i_tables.huff_val);
    mkConnection(i_dequant.quant, i_tables.quant);

    //data path wiring

    rule r_bytes_in;
        let pkg <- i_axis_rd.pkg.get;
        i_markers.bytes.put(pkg.data);
        i_csrs.internal.byte_in();
    endrule

    mkConnection(i_markers.seg,            i_frames.seg);
    mkConnection(i_markers.ecs,            i_bits.ecs);
    mkConnection(i_frames.scan,            i_huff.huff_scan);
    mkConnection(i_frames.frame,           i_untiler.frame);
    mkConnection(i_huff.sym,               i_rld.data.request);
    mkConnection(i_rld.data.response,      i_dequant.data.request);
    mkConnection(i_dequant.data.response,  i_dezz.coef);
    mkConnection(i_dezz.sample,            i_idct.data.request);

    //frame-level control between the parsers and the dequantizer, all sources are registered pulses

    (* fire_when_enabled *)
    rule r_skip (i_frames.skip_req matches tagged Valid .parity);
        i_markers.skip(parity);
    endrule

    (* fire_when_enabled *)
    rule r_scan_done (i_dequant.scan_done);
        i_frames.scan_done;
    endrule

    Reg#(Bit#(6))    rg_idx <- mkReg(0);
    Reg#(BlockTag_t) rg_tag <- mkRegU;

    //rejoin pixel samples with their block tag
    rule r_samples;
        let s <- i_idct.data.response.get;
        BlockTag_t tag = rg_tag;
        if(rg_idx == 0) begin
            let t <- i_dezz.tag.get;
            tag    = t;
            rg_tag <= t;
        end
        i_untiler.sample.put(CompSample_t {
            tag:    tag,
            sample: s
        });
        rg_idx <= rg_idx + 1;
    endrule

    //control and status

    Reg#(UInt#(4))   rg_in_flight <- mkReg(0);
    Reg#(DecError_t) rg_err_last  <- mkReg(None);
    PulseWire        pw_done      <- mkPulseWire;

    rule r_pix_out;
        let p <- i_untiler.pix_out.get;
        i_axis_wr.pkg.put(AXI4_Stream_Pkg {
            data: pack(p.pixel),
            user: 0,
            keep: unpack(-1),
            dest: 0,
            last: p.last,
            id:   ?
        });
        i_csrs.internal.pixel_out();
        if(p.last) pw_done.send;
    endrule

    //error events of the stages, one is reported when several coincide
    Maybe#(DecError_t) err = isValid(i_markers.error) ? i_markers.error
                           : (isValid(i_frames.error) ? i_frames.error : i_huff.error);

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_status;
        Bool start = i_frames.scan_start;
        Bool busy  = rg_in_flight != 0;
        rg_in_flight <= rg_in_flight + (start ? 1 : 0) - (pw_done ? 1 : 0);
        if(err matches tagged Valid .e) rg_err_last <= e;

        i_csrs.internal.status(busy, i_frames.info, rg_err_last);
        i_csrs.internal.events(start && !busy, pw_done, isValid(err));
    endrule

    //interfaces

    interface s_axis       = i_axis_rd.fab;
    interface m_axis       = i_axis_wr.fab;
    interface s_axi_cfg_rd = i_axi_csrs.s_rd;
    interface s_axi_cfg_wr = i_axi_csrs.s_wr;

    method irq  = i_axi_csrs.irqs[0];
    method busy = rg_in_flight != 0;

endmodule

endpackage
