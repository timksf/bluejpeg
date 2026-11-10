package DUProc;

import Clocks :: *;
import Assert :: *;
import GetPut :: *;
import Gearbox :: *;
import FIFO :: *;
import Connectable :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import EncoderUtil :: *;
import Types :: *;
import ZigZag :: *;
import Quantize :: *;
import PrintUtil :: *;
import DCT2D_Optimized :: *;
import DUDebug :: *;

interface DUProc_ifc#(numeric type pixel_bits);
    interface Put#(PixType_t) du_mode;

    interface Client#(QuantTableIdx_t, Int#(32)) qtable;
    interface Server#(UInt#(pixel_bits), Int#(TAdd#(pixel_bits, 7))) data;
endinterface

interface DUProcLegacy_ifc#(numeric type pixel_bits, numeric type dct_bits);
    interface Put#(PixType_t) du_mode;

    interface Client#(QuantTableIdx_t, Int#(32)) qtable;
    interface Server#(UInt#(pixel_bits), Int#(dct_bits)) data;
endinterface

typedef struct {
    Clock                  slow_clock;
    Reset                  slow_reset;
    Bool                   buffer_in;
    NumProxy_t#(dct_scale) _dct_scale;
    Bool                   scale_in_dct;
    Bool                   transpose_in_dct;
    NumProxy_t#(q_scale)   _q_scale;
    Bool                   dct_safe_arith;
    Bool                   debug;
} DUProcCfg_t#(numeric type dct_scale, numeric type q_scale);

function Int#(bits) center_pixel(UInt#(bits) pixel);
    UInt#(bits) center = 1 << fromInteger(valueOf(bits) - 1);
    return unpack(pack(pixel - center));
endfunction

module mkDUProc#(DUProcCfg_t#(dct_scale, q_scale) cfg)(DUProcLegacy_ifc#(pixel_bits, dct_bits))
    provisos(
        Add#(a__, q_scale, 32),
        Add#(pixel_bits, b__, dct_bits)
    );

    staticAssert(valueOf(pixel_bits) > 0, "DUProc pixel width must be greater than zero");
    staticAssert(valueOf(dct_scale) > 0, "DUProc DCT scale must be greater than zero");
    staticAssert(valueOf(q_scale) > 0, "DUProc quantization scale must be greater than zero");
    staticAssert(valueOf(q_scale) <= 32, "DUProc quantization scale must not exceed 32 bits");

    Clock fast_clock <- exposeCurrentClock;
    Reset fast_reset <- exposeCurrentReset;

    FIFO#(UInt#(pixel_bits)) f_i;
    FIFO#(Int#(dct_bits))    f_dct <- mkFIFO;

    DUDebug_ifc#(UInt#(pixel_bits), 8, 8) i_du_dbg_0 = ?;
    DUDebug_ifc#(Int#(dct_bits), 8, 8)    i_du_dbg_1 = ?;
    DUDebug_ifc#(Int#(dct_bits), 8, 8)    i_du_dbg_2 = ?;
    DUDebug_ifc#(Int#(dct_bits), 64, 1)   i_du_dbg_3 = ?;
    if(cfg.debug) begin
        i_du_dbg_0 <- mkDUDebug("BEFORE DCT");
        i_du_dbg_1 <- mkDUDebug("AFTER DCT");
        i_du_dbg_2 <- mkDUDebug("AFTER QUANT");
        i_du_dbg_3 <- mkDUDebug("AFTER ZIGZAG");
    end

    //allows the DCT to run in a slower clock domain as it is served with rows not individual pixels
    Gearbox#(1, 8, Int#(dct_bits)) i_gear_i <- mk1toNGearbox(fast_clock,      fast_reset,     cfg.slow_clock, cfg.slow_reset);
    Gearbox#(8, 1, Int#(dct_bits)) i_gear_o <- mkNto1Gearbox(cfg.slow_clock,  cfg.slow_reset, fast_clock,     fast_reset);

    //processing submodules
    DCT2DOpt_ifc#(dct_bits) i_dct   <- mkDCT2D_Opt(cfg._dct_scale, False, !cfg.scale_in_dct, cfg.transpose_in_dct, cfg.dct_safe_arith, clocked_by cfg.slow_clock, reset_by cfg.slow_reset);
    Quant_ifc#(dct_bits)    i_quant <- mkQuantize_RT(cfg._q_scale, False);
    Zigzag_ifc#(dct_bits)   i_zz    <- mkZigZag_Opt(False, !cfg.transpose_in_dct);

    if(cfg.buffer_in)
        f_i <- mkFIFO;
    else
        f_i <- mkBypassFIFO;

    if(cfg.debug)
        mkConnection(toGet(f_i), i_du_dbg_0.pix_i);

    rule r_mean_shift;
        UInt#(pixel_bits) pix = 0;
        if(!cfg.debug) begin
            pix = f_i.first;
            f_i.deq;
        end else
            pix <- i_du_dbg_0.pix_o.get;
        f_dct.enq(signExtend(center_pixel(pix)));
    endrule

    //DCT deserialization pix -> row
    mkConnection(toGet(f_dct), gearbox_fast_put(i_gear_i));

    //slow clock domain
    mkConnection(gearbox_slow_get(i_gear_i), i_dct.data.request);

    //either row or col, depending on whether DCT transposes its output
    mkConnection(i_dct.data.response, gearbox_slow_put(i_gear_o));

    //DCT deserialization vec -> pix
    if(!cfg.debug)
        mkConnection(gearbox_fast_get(i_gear_o), i_quant.data.request);
    else begin
        mkConnection(gearbox_fast_get(i_gear_o),  i_du_dbg_1.pix_i);
        mkConnection(i_du_dbg_1.pix_o,            i_quant.data.request);
    end

//
    if(!cfg.debug)
        mkConnection(i_quant.data.response, i_zz.data.request);
    else begin
        mkConnection(i_quant.data.response, i_du_dbg_2.pix_i);
        mkConnection(i_du_dbg_2.pix_o, i_zz.data.request);
        mkConnection(i_zz.data.response, i_du_dbg_3.pix_i);
    end

    Get#(Int#(dct_bits)) ifc_out = cfg.debug ? i_du_dbg_3.pix_o : i_zz.data.response;

    interface du_mode = i_quant.du_mode;
    interface qtable = i_quant.qtable;

    interface Server data;
        interface request   = toPut(f_i);
        interface response  = ifc_out;
    endinterface

endmodule


module mkDUProc_Opt#(DUProcCfg_t#(dct_scale, q_scale) cfg)(DUProc_ifc#(pixel_bits))
    provisos(
        Add#(a__, q_scale, 32)
    );

    staticAssert(valueOf(pixel_bits) > 0, "DUProc pixel width must be greater than zero");
    staticAssert(valueOf(dct_scale) > 0, "DUProc DCT scale must be greater than zero");
    staticAssert(valueOf(q_scale) > 0, "DUProc quantization scale must be greater than zero");
    staticAssert(valueOf(q_scale) <= 32, "DUProc quantization scale must not exceed 32 bits");

    Clock fast_clock <- exposeCurrentClock;
    Reset fast_reset <- exposeCurrentReset;

    FIFO#(UInt#(pixel_bits)) f_i;
    FIFO#(Int#(pixel_bits))  f_dct <- mkFIFO;

    DUDebug_ifc#(UInt#(pixel_bits), 8, 8)           i_du_dbg_0 = ?;
    DUDebug_ifc#(Int#(TAdd#(pixel_bits, 7)), 8, 8)  i_du_dbg_1 = ?;
    DUDebug_ifc#(Int#(TAdd#(pixel_bits, 7)), 8, 8)  i_du_dbg_2 = ?;
    DUDebug_ifc#(Int#(TAdd#(pixel_bits, 7)), 64, 1) i_du_dbg_3 = ?;
    if(cfg.debug) begin
        i_du_dbg_0 <- mkDUDebug("BEFORE DCT");
        i_du_dbg_1 <- mkDUDebug("AFTER DCT");
        i_du_dbg_2 <- mkDUDebug("AFTER QUANT");
        i_du_dbg_3 <- mkDUDebug("AFTER ZIGZAG");
    end

    //allows the DCT to run in a slower clock domain as it is served with rows not individual pixels
    Gearbox#(1, 8, Int#(pixel_bits))           i_gear_i <- mk1toNGearbox(fast_clock,     fast_reset,     cfg.slow_clock, cfg.slow_reset);
    Gearbox#(8, 1, Int#(TAdd#(pixel_bits, 7))) i_gear_o <- mkNto1Gearbox(cfg.slow_clock, cfg.slow_reset, fast_clock,     fast_reset);

    //processing submodules
    DCT2DOptRigid_ifc#(pixel_bits)    i_dct   <- mkDCT2D_Opt_rigid(cfg._dct_scale, False, !cfg.scale_in_dct, cfg.transpose_in_dct, cfg.dct_safe_arith, clocked_by cfg.slow_clock, reset_by cfg.slow_reset);
    Quant_ifc#(TAdd#(pixel_bits, 7))  i_quant <- mkQuantize_RT(cfg._q_scale, False);
    Zigzag_ifc#(TAdd#(pixel_bits, 7)) i_zz    <- mkZigZag_Opt(False, !cfg.transpose_in_dct);

    if(cfg.buffer_in)
        f_i <- mkFIFO;
    else
        f_i <- mkBypassFIFO;

    if(cfg.debug)
        mkConnection(toGet(f_i), i_du_dbg_0.pix_i);

    rule r_mean_shift;
        UInt#(pixel_bits) pix = 0;
        if(!cfg.debug) begin
            pix = f_i.first;
            f_i.deq;
        end else
            pix <- i_du_dbg_0.pix_o.get;
        f_dct.enq(center_pixel(pix));
    endrule

    //DCT deserialization pix -> row
    mkConnection(toGet(f_dct), gearbox_fast_put(i_gear_i));

    //slow clock domain
    mkConnection(gearbox_slow_get(i_gear_i), i_dct.data.request);

    //either row or col, depending on whether DCT transposes its output
    mkConnection(i_dct.data.response, gearbox_slow_put(i_gear_o));

    //DCT deserialization vec -> pix
    if(!cfg.debug)
        mkConnection(gearbox_fast_get(i_gear_o), i_quant.data.request);
    else begin
        mkConnection(gearbox_fast_get(i_gear_o), i_du_dbg_1.pix_i);
        mkConnection(i_du_dbg_1.pix_o,           i_quant.data.request);
    end

//
    if(!cfg.debug)
        mkConnection(i_quant.data.response, i_zz.data.request);
    else begin
        mkConnection(i_quant.data.response, i_du_dbg_2.pix_i);
        mkConnection(i_du_dbg_2.pix_o, i_zz.data.request);
        mkConnection(i_zz.data.response, i_du_dbg_3.pix_i);
    end

    Get#(Int#(TAdd#(pixel_bits, 7))) ifc_out = cfg.debug ? i_du_dbg_3.pix_o : i_zz.data.response;

    interface du_mode = i_quant.du_mode;
    interface qtable = i_quant.qtable;

    interface Server data;
        interface request   = toPut(f_i);
        interface response  = ifc_out;
    endinterface

endmodule

endpackage
