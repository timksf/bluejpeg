package HuffEncoder;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;
import ConfigReg :: *;

import Types :: *;
import Util :: *;

typedef struct {
    PixType_t mode;
    Bool      is_last;
} HuffDUMeta_t deriving(Eq, Bits, FShow);

interface HuffEncoder_ifc#(numeric type bits);
    interface Put#(HuffDUMeta_t) du_meta;
    method Action rewind();

    //combinational table read clients, connected to TableStorage
    interface Client#(HuffCodeDCIdx_t, HuffTableEntry_t) huff_dc;
    interface Client#(HuffCodeACIdx_t, HuffTableEntry_t) huff_ac;

    interface Server#(RLETag_t#(bits), HuffCode_t) data;
endinterface

module mkHuffEncoder(HuffEncoder_ifc#(bits))
    provisos(
        Add#(1, a__, bits), //bits >= 1
        Add#(b__, bits, 32), //bits <= 32 (for zeroExtend to Bit#(32))
        Add#(bits, c__, TExp#(TLog#(bits))),  // for flog2/clz_gen
        Add#(d__, 5, TAdd#(TLog#(bits), 1))   // for truncate in calc_magnitude
    );

    FIFO#(RLETag_t#(bits)) f_in  <- mkPipelineFIFO;
    FIFO#(HuffCode_t)      f_out <- mkPipelineFIFO;

    FIFO#(HuffDUMeta_t)     f_meta       <- mkSizedFIFO(4);
    Reg#(Bit#(6))   rg_coeff_idx    <- mkReg(0);

    //combinational table read wires
    Wire#(HuffCodeDCIdx_t)    w_dc_req  <- mkWire;
    Wire#(HuffTableEntry_t)   w_dc_resp <- mkWire;
    Wire#(HuffCodeACIdx_t)    w_ac_req  <- mkWire;
    Wire#(HuffTableEntry_t)   w_ac_resp <- mkWire;

    //calculate magnitude (number of significant bits) of a signed value
    //this is equivalent to floor(log2(abs(val))) + 1 for val != 0
    //for val == 0, abs_bits is all zeros so no bit matches and mag = 0
    function ActionValue#(Bit#(5)) calc_magnitude(Int#(bits) val);
        actionvalue
            let abs_val = abs(val);
            Bit#(5) mag = 0;
            if(abs_val != 0) begin
                let l <- flog2(pack(abs_val));
                mag = truncate(l) + 1;
            end
            return mag;
        endactionvalue
    endfunction

    //calculate extra bits for a signed value per JPEG F.1.2.1.1
    //positive values: lower mag bits of val
    //negative values: lower mag bits of bitwise complement of abs(val)
    function Bit#(bits) calc_extra_bits(Int#(bits) val);
        let abs_bits = pack(abs(val));
        return (val < 0) ? ~abs_bits : abs_bits;
    endfunction

    //table lookups based on current Luma/Chroma mode
    function HuffTableEntry_t dc_lookup = w_dc_resp;

    function HuffTableEntry_t ac_lookup = w_ac_resp;

    //drive table address wires by peeking at input
    //the symbol/magnitude is computed combinationally from f_in.first
    rule r_drive_table_addr;
        let tag = f_in.first;

        //DC address: magnitude of the DC diff value
        Bit#(4) dc_addr = 0;
        case (tag) matches
            tagged DCDiff .val: begin
                //inline magnitude: count significant bits
                Bit#(bits) abs_val = pack(abs(val));
                Bit#(5) m = 0;
                for (Integer i = 0; i < valueOf(bits); i = i + 1)
                    if (abs_val[i] == 1) m = fromInteger(i + 1);
                dc_addr = truncate(m);
            end
        endcase
        w_dc_req <= HuffCodeDCIdx_t { pt: f_meta.first.mode, idx: dc_addr };

        //AC address: RRRRSSSS symbol, ZRL=F0, EOB=00
        Bit#(8) ac_addr = 0;
        case (tag) matches
            tagged AC .ac: begin
                Bit#(bits) abs_val = pack(abs(ac.val));
                Bit#(5) m = 0;
                for (Integer i = 0; i < valueOf(bits); i = i + 1)
                    if (abs_val[i] == 1) m = fromInteger(i + 1);
                ac_addr = {ac.run, truncate(m)};
            end
            tagged ZRL:  ac_addr = 8'hF0;
            tagged EOB:  ac_addr = 8'h00;
        endcase
        w_ac_req <= HuffCodeACIdx_t { pt: f_meta.first.mode, idx: ac_addr };
    endrule

    rule r_encode;
        let tag = f_in.first; f_in.deq;

        HuffCode_t out = HuffCode_t { huffcode: 0, huffsize: 0, last: False };
        Bit#(7) next_idx = 0;

        case (tag) matches
            tagged DCDiff .val: begin
                Bit#(5) mag <- calc_magnitude(val);
                HuffTableEntry_t entry = dc_lookup;
                Bit#(bits) extra = calc_extra_bits(val);
                Bit#(32) code = (zeroExtend(entry.code) << mag) | zeroExtend(extra & ((1 << mag) - 1));
                out.huffcode = code;
                out.huffsize = entry.size + mag;
                next_idx = 1;
            end

            tagged AC .ac: begin
                Bit#(5) mag_ac <- calc_magnitude(ac.val);
                Bit#(4) mag4 = truncate(mag_ac);
                Bit#(8) symbol = {ac.run, mag4}; //RRRRSSSS
                HuffTableEntry_t entry = ac_lookup;
                Bit#(bits) extra = calc_extra_bits(ac.val);
                Bit#(32) code = (zeroExtend(entry.code) << mag_ac) | zeroExtend(extra & ((1 << mag_ac) - 1));
                out.huffcode = code;
                out.huffsize = entry.size + mag_ac;
                next_idx = zeroExtend(rg_coeff_idx) + zeroExtend(ac.run) + 1;
            end

            tagged ZRL: begin
                HuffTableEntry_t entry = ac_lookup;
                out.huffcode = zeroExtend(entry.code);
                out.huffsize = entry.size;
                next_idx = zeroExtend(rg_coeff_idx) + 16;
            end

            tagged EOB: begin
                HuffTableEntry_t entry = ac_lookup;
                out.huffcode = zeroExtend(entry.code);
                out.huffsize = entry.size;
                next_idx = 0;
            end
        endcase

        //detect end-of-block: EOB always ends a block;
        //AC/ZRL end a block if the coefficient index wraps past 63
        Bool is_eob = (tag matches tagged EOB ? True : False);
        Bool is_end_of_block = is_eob || (next_idx >= 64);

        out.last = f_meta.first.is_last && is_end_of_block;

        if (is_end_of_block) f_meta.deq;

        rg_coeff_idx <= truncate(next_idx); //truncation wraps >= 64 to 0
        f_out.enq(out);
    endrule

    method Action rewind();
        rg_coeff_idx <= 0;
        f_meta.clear;
        f_in.clear();
        f_out.clear();
    endmethod

    interface du_meta = toPut(f_meta);

    interface huff_dc = toGPClient(asReg(w_dc_req), asReg(w_dc_resp));
    interface huff_ac = toGPClient(asReg(w_ac_req), asReg(w_ac_resp));

    interface data = toGPServer(f_in, f_out);

endmodule

endpackage