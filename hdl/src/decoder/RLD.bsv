package RLD;

import FIFO :: *;
import FIFOF :: *;
import Vector :: *;
import GetPut :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import DecoderTypes :: *;

interface RLD_ifc;
    interface Server#(SymToken_t, CoefToken_t) data;
endinterface

/*
 * Run-length decoding, the inverse of RLE. Zero runs are already resolved
 * into coefficient indices by the Huffman decoder, so what remains is value
 * reconstruction (T.81 F.2.2.1 EXTEND and DC prediction) in a rigid
 * three-stage pipeline.
 *
 *   align    magnitude bits shifted down to their size, sign taken from the
 *            first magnitude bit (always bit 10 of the MSB-aligned window
 *            bits, 0 means negative), mask of size ones
 *   extend   negative values become bits - mask
 *   predict  per-component DC predictor added
 *
 * The first symbol of a scan resets all predictors in band, so frames can
 * overlap in the pipeline without a rewind.
 */
module mkRLD(RLD_ifc);

    FIFO#(SymToken_t)   f_in  <- mkBypassFIFO;
    FIFOF#(CoefToken_t) f_out <- mkGFIFOF(True, False);

    Vector#(2, Reg#(SymToken_t)) rg_tok   <- replicateM(mkRegU);
    Vector#(2, Reg#(Bool))       rg_valid <- replicateM(mkReg(False));
    Reg#(UInt#(11))              rg_bits  <- mkRegU;
    Reg#(UInt#(11))              rg_mask  <- mkRegU;
    Reg#(Bool)                   rg_neg   <- mkRegU;
    Reg#(Coef_t)                 rg_mag   <- mkRegU;
    Vector#(3, Reg#(Coef_t))     rg_pred  <- replicateM(mkReg(0));
    PulseWire                    pw_input <- mkPulseWire;

    Bool advance = f_out.notFull;

    rule r_align (advance);
        let t = f_in.first; f_in.deq;
        rg_tok[0] <= t;
        rg_bits   <= unpack(t.raw >> (11 - t.s));
        rg_mask   <= unpack(~(11'h7FF << t.s));
        rg_neg    <= t.s != 0 && t.raw[10] == 0;
        pw_input.send;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_valid (advance);
        rg_valid[0] <= pw_input;
        rg_valid[1] <= rg_valid[0];
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_extend (advance);
        Int#(12) b = unpack(zeroExtend(pack(rg_bits)));
        Int#(12) m = unpack(zeroExtend(pack(rg_mask)));
        rg_mag    <= rg_neg ? b - m : b;
        rg_tok[1] <= rg_tok[0];
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_predict (advance && rg_valid[1]);
        let    t   = rg_tok[1];
        Coef_t val = rg_mag;
        if(t.is_dc) begin
            Vector#(3, Coef_t) pred = t.first ? replicate(0) : readVReg(rg_pred);
            val = pred[t.pos.comp] + rg_mag;
            pred[t.pos.comp] = val;
            writeVReg(rg_pred, pred);
        end
        f_out.enq(CoefToken_t {
            pos:     t.pos,
            val:     val,
            has_val: t.has_val
        });
    endrule

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage
