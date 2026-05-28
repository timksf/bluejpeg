package DUProc;

import Clocks :: *;
import GetPut :: *;
import Gearbox :: *;
import FIFO :: *;
import Connectable :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import Util :: *;
import Types :: *;
import ZigZag :: *;
import Quantize :: *;
import PrintUtil :: *;
import DCT2D_Optimized :: *;

import DUDebug :: *;

interface DUProc_t#(numeric type bits);
    method Action force_rewind(); //for recovery purposes
    interface Put#(PixType_t) du_mode;

    interface Client#(QuantTableIdx_t, Int#(32)) qtable;
    interface Server#(Int#(bits), Int#(bits)) data;
endinterface

typedef struct {
    Clock                   slow_clock;
    Reset                   slow_reset;
    Bool                    buffer_in;
    NumProxy#(dct_scale)    _dct_scale;
    Bool                    scale_in_dct;
    Bool                    transpose_in_dct;
    NumProxy#(q_scale)      _q_scale;
    Bool                    dct_safe_arith;
    Bool                    debug;
} DUProcCfg#(numeric type dct_scale, numeric type q_scale);

module mkDUProc#(DUProcCfg#(dct_scale, q_scale) cfg)(DUProc_t#(bits))
    provisos(
        Add#(a__, q_scale, 32)         //q_scale <= 32
    );

    Clock fast_clock <- exposeCurrentClock;
    Reset fast_reset <- exposeCurrentReset;

    FIFO#(Int#(bits)) f_i;
    FIFO#(Int#(bits)) f_dct <- mkPipelineFIFO;

    DUDebug_ifc#(Int#(bits), 8, 8)  du_dbg_0;
    DUDebug_ifc#(Int#(bits), 8, 8)  du_dbg_1;
    DUDebug_ifc#(Int#(bits), 8, 8)  du_dbg_2;
    DUDebug_ifc#(Int#(bits), 64, 1) du_dbg_3;
    if(cfg.debug) begin
        du_dbg_0 <- mkDUDebug("BEFORE DCT");
        du_dbg_1 <- mkDUDebug("AFTER DCT");
        du_dbg_2 <- mkDUDebug("AFTER QUANT");
        du_dbg_3 <- mkDUDebug("AFTER ZIGZAG");
    end

    //allows the DCT to run in a slower clock domain as it is served with rows not individual pixels
    Gearbox#(1, 8, Int#(bits)) gear_i <- mk1toNGearbox(fast_clock,      fast_reset,     cfg.slow_clock, cfg.slow_reset);
    Gearbox#(8, 1, Int#(bits)) gear_o <- mkNto1Gearbox(cfg.slow_clock,  cfg.slow_reset, fast_clock,     fast_reset);

    //processing submodules
    DCT2DOpt_ifc#(bits)         i_dct   <- mkDCT2D_Opt(cfg._dct_scale, False, !cfg.scale_in_dct, cfg.transpose_in_dct, cfg.dct_safe_arith, clocked_by cfg.slow_clock, reset_by cfg.slow_reset);
    Quant_ifc#(bits)            i_quant <- mkQuantize_RT(cfg._q_scale, True); //quantization should explicitly buffer inputs for timing
    Zigzag_ifc#(bits)           i_zz    <- mkZigZag_Opt(False, !cfg.transpose_in_dct);

    if(cfg.buffer_in)
        f_i <- mkPipelineFIFO;
    else 
        f_i <- mkBypassFIFO;

    if(cfg.debug)
        mkConnection(toGet(f_i), du_dbg_0.pix_i);

    rule rmean_shift;
        Int#(bits) pix = 0;
        if(!cfg.debug) begin
            pix = f_i.first;
            f_i.deq;
        end else 
            pix <- du_dbg_0.pix_o.get;
        pix = pix - 128;
        f_dct.enq(pix);
    endrule
    
    //DCT deserialization pix -> row
    mkConnection(toGet(f_dct), gearbox_fast_put(gear_i));

    //slow clock domain
    mkConnection(gearbox_slow_get(gear_i), i_dct.data.request);

    //either row or col, depending on whether DCT transposes its output
    mkConnection(i_dct.data.response, gearbox_slow_put(gear_o));

    //DCT deserialization vec -> pix
    if(!cfg.debug)
        mkConnection(gearbox_fast_get(gear_o), i_quant.data.request);
    else begin
        mkConnection(gearbox_fast_get(gear_o),  du_dbg_1.pix_i);
        mkConnection(du_dbg_1.pix_o,            i_quant.data.request);
    end

    //
    if(!cfg.debug)
        mkConnection(i_quant.data.response, i_zz.data.request);
    else begin
        mkConnection(i_quant.data.response, du_dbg_2.pix_i);
        mkConnection(du_dbg_2.pix_o, i_zz.data.request);
        mkConnection(i_zz.data.response, du_dbg_3.pix_i);
    end
    
    Get#(Int#(bits)) ifc_out = cfg.debug ? du_dbg_3.pix_o : i_zz.data.response;

    interface du_mode = i_quant.du_mode;
    interface qtable = i_quant.qtable;

    interface Server data;
        interface request   = toPut(f_i);
        interface response  = ifc_out;
    endinterface

endmodule


endpackage