package IDCTProc;

import FIFO :: *;
import Clocks :: *;
import Gearbox :: *;
import Vector :: *;
import GetPut :: *;
import Connectable :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import Types :: *;
import EncoderUtil :: *;
import IDCT :: *;

interface IDCTProc_ifc#(numeric type bits);
    interface Server#(Int#(bits), UInt#(8)) data;
endinterface

typedef struct {
    Clock              slow_clock;
    Reset              slow_reset;
    NumProxy_t#(cfrac) _idct_scale;
    NumProxy_t#(dfrac) _dequant_scale;
    Bool               shallow;
} IDCTProcCfg_t#(numeric type cfrac, numeric type dfrac);

/*
 * Block-sample processing around the IDCT, the counterpart of mkDUProc_Opt.
 * Dequantized coefficients arrive one per cycle in column-major order. A
 * 1-to-8 gearbox collects a column per slow cycle for the IDCT in
 * slow_clock, and an 8-to-1 gearbox returns its pixel rows one sample per
 * cycle in row-major order. As in the encoder, slow_clock is the main clock
 * divided by eight with aligned edges (or the main clock itself), so the
 * gearboxes need no synchronizers and the IDCT keeps up with one sample per
 * main clock cycle.
 */
module mkIDCTProc#(IDCTProcCfg_t#(cfrac, dfrac) cfg)(IDCTProc_ifc#(bits))
    provisos(
        NumAlias#(TAdd#(bits, TSub#(IDCTPass2Int, IDCTPass1Int)), bits_out),
        Add#(bits, a__, bits_out),
        Add#(bits, IDCTCoeffBits#(cfrac), mul_in),
        Add#(bits_out, IDCTCoeffBits#(cfrac), mul_out),
        Add#(bits, b__, mul_in),
        Add#(bits_out, c__, mul_out),
        Add#(8, d__, bits_out)
    );

    Clock fast_clock <- exposeCurrentClock;
    Reset fast_reset <- exposeCurrentReset;

    //registered input, so the gearbox element enables only see local state
    FIFO#(Int#(bits)) f_i <- mkFIFO;

    Gearbox#(1, 8, Int#(bits)) i_gear_i <- mk1toNGearbox(fast_clock, fast_reset, cfg.slow_clock, cfg.slow_reset);
    Gearbox#(8, 1, UInt#(8))   i_gear_o <- mkNto1Gearbox(cfg.slow_clock, cfg.slow_reset, fast_clock, fast_reset);

    IDCT2D_ifc#(bits) i_idct <- mkIDCT2D(cfg._idct_scale, cfg._dequant_scale, cfg.shallow, clocked_by cfg.slow_clock, reset_by cfg.slow_reset);

    //coefficient serialization sample -> column
    mkConnection(toGet(f_i), gearbox_fast_put(i_gear_i));

    //slow clock domain
    mkConnection(gearbox_slow_get(i_gear_i), i_idct.data.request);
    mkConnection(i_idct.data.response,       gearbox_slow_put(i_gear_o));

    interface Server data;
        interface request  = toPut(f_i);
        interface response = gearbox_fast_get(i_gear_o);
    endinterface

endmodule

endpackage
