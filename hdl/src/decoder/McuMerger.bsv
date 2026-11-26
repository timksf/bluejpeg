package McuMerger;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import RegFile :: *;
import SpecialFIFOs :: *;

import Types :: *;
import DecoderTypes :: *;

interface McuMerger_ifc;
    interface Put#(CompSample_t) comp_sample;
    interface Get#(PixelOut_t)   pixel;
endinterface

function YCbCr_t ycbcr(UInt#(8) y, UInt#(8) cb, UInt#(8) cr) = YCbCr_t {
    y:  y,
    cb: cb,
    cr: cr
};

/*
 * Inverse of the encoder's channel splitter and DU dispatcher. Component
 * blocks arrive sample by sample as Y, Cb, Cr per MCU. Y and Cb samples are
 * kept in a 128-entry LUTRAM, and each Cr sample leaves as one YCbCr pixel
 * together with its Y and Cb sample, in block order. One MCU of storage
 * suffices because the next Y block only starts after the last Cr sample. A
 * block that ends its MCU early (a grayscale stream) leaves with neutral
 * chroma. Without chroma the merger is a registered map.
 */
module mkMcuMerger#(Bool en_chroma)(McuMerger_ifc);
    McuMerger_ifc ifc;
    if(en_chroma)
        ifc <- mkMcuMergerActive;
    else
        ifc <- mkMcuMergerLuma;
    return ifc;
endmodule

module mkMcuMergerActive(McuMerger_ifc);

    RegFile#(Bit#(7), UInt#(8)) i_samples <- mkRegFileWCF(0, 127);
    FIFO#(CompSample_t)         f_in      <- mkFIFO;
    FIFO#(PixelOut_t)           f_out     <- mkFIFO;
    Reg#(Bit#(6))               rg_idx    <- mkReg(0);

    rule r_merge;
        let s = f_in.first; f_in.deq;
        Bit#(7) y_addr  = {1'b0, rg_idx};
        Bit#(7) cb_addr = {1'b1, rg_idx};

        if(s.tag.comp != 2 && !s.tag.mcu_end) begin
            i_samples.upd(s.tag.comp == 0 ? y_addr : cb_addr, s.sample);
        end else begin
            let y  = s.tag.comp == 0 ? s.sample : i_samples.sub(y_addr);
            let cb = s.tag.comp == 2 ? i_samples.sub(cb_addr) : 128;
            let cr = s.tag.comp == 2 ? s.sample : 128;
            f_out.enq(PixelOut_t {
                pixel: ycbcr(y, cb, cr),
                last:  s.tag.last && rg_idx == 63
            });
        end
        rg_idx <= rg_idx + 1;
    endrule

    interface comp_sample = toPut(f_in);
    interface pixel       = toGet(f_out);

endmodule

module mkMcuMergerLuma(McuMerger_ifc);

    FIFO#(PixelOut_t) f_out  <- mkFIFO;
    Reg#(Bit#(6))     rg_idx <- mkReg(0);

    interface Put comp_sample;
        method Action put(CompSample_t s);
            f_out.enq(PixelOut_t {
                pixel: ycbcr(s.sample, 128, 128),
                last:  s.tag.last && rg_idx == 63
            });
            rg_idx <= rg_idx + 1;
        endmethod
    endinterface

    interface pixel = toGet(f_out);

endmodule

endpackage
