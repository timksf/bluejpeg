package DecTableStorage;

import FIFO :: *;
import FIFOF :: *;
import Vector :: *;
import RegFile :: *;
import GetPut :: *;
import ClientServer :: *;

import EncoderUtil :: *;
import DecoderTypes :: *;

interface DecTableStorage_ifc;
    //writes from the frame parser
    method Action write_quant(QuantTableId_t tq, UInt#(6) k, UInt#(8) q);
    method Action huff_start(Bool ac, HuffTableId_t id);
    method Action huff_count(UInt#(8) n);
    method Action huff_value(UInt#(8) idx, Bit#(8) v);

    //to the Huffman decoder, limits are registers for the parallel length search
    method HuffLimits_t                      huff_limits(Bool ac, HuffTableId_t id);
    interface Server#(HuffValIdx_t, Bit#(8)) huff_val;

    //lookahead for short codes, read with registered window bits, and whether a table is still being filled
    method HuffLook_t huff_look(Bool ac, HuffTableId_t id, Bit#(HuffLookBits) bits);
    method Bool       huff_busy;

    //to the dequantizer
    interface Server#(QuantIdx_t, UInt#(8)) quant;
endinterface

//lookahead fill request of one table, the counts of the code lengths the lookahead covers and the value total
typedef struct {
    Bit#(2)                         tbl;
    Vector#(HuffLookBits, UInt#(8)) counts;
    UInt#(9)                        total;
} LookFill_t deriving(Bits, Eq, FShow);

//register that reads 0 and drops writes, stands in for tables a configuration leaves out
module mkNullReg(Reg#(t))
    provisos(
        Bits#(t, t_w)
    );
    method Action _write(t x) = noAction;
    method t _read = unpack(0);
endmodule

/*
 * Decoder tables, the counterpart of the encoder's TableStorage. The parser
 * writes them while it walks DHT and DQT segments, nothing is preset.
 *
 * Huffman tables use a compare-friendly canonical form (ITU T.81 F.2.2.3).
 * Per code length l there is LIMIT(l), one past the largest code of that
 * length, and OFFSET(l) = VALPTR(l) - MINCODE(l) modulo 256, both derived
 * while the sixteen BITS counts stream in and written one stage later. Only
 * the low l + 1 bits of LIMIT(l) are significant and only those are read, so
 * synthesis trims the rest of each register. Lengths without codes get
 * LIMIT(l) = MINCODE(l), and an unprogrammed table (all zero) matches nothing. HUFFVAL lives in a 16-entry DC and a 256-entry
 * AC LUTRAM, raw quantization entries in a 64-entry LUTRAM per table.
 *
 * Like TableStorage, the LUTRAM servers answer in the cycle of the request,
 * so clients register their address and get a clean LUTRAM read stage.
 *
 * A lookahead table per Huffman table resolves every code of up to
 * HuffLookBits bits from the top window bits alone, with its length and
 * symbol. A fill engine writes all 256 entries of a table in increasing
 * order while the DHT values stream in. Canonical codes increase with the
 * entry index, so each value covers the next 2^(8 - l) entries, and the
 * entries after the last short code are marked invalid. Walking every entry
 * makes a clearing pass unnecessary. Each table hands the engine a request
 * with its short code counts once its sixteen counts are in, and its values
 * queue behind those of the table before. huff_busy holds off decoding until
 * the last table is complete, and the parser stalls while the engine catches
 * up. Without en_look there is neither lookahead table nor fill engine,
 * huff_look reads as a miss and huff_busy stays low.
 * Without chroma, only table id 0 is stored and other ids alias to it.
 */
module mkDecTableStorage#(Bool en_chroma, Bool en_look)(DecTableStorage_ifc);

    Integer n_tables = en_chroma ? 2 : 1;

    //index {ac, id}
    Vector#(4, Vector#(16, Reg#(UInt#(17)))) rg_limit  = newVector;
    Vector#(4, Vector#(16, Reg#(Bit#(8))))   rg_offset = newVector;
    for(Integer t = 0; t < 4; t = t + 1) begin
        if(t % 2 < n_tables) begin
            rg_limit[t]  <- replicateM(mkReg(0));
            rg_offset[t] <- replicateM(mkReg(0));
        end else begin
            rg_limit[t]  <- replicateM(mkNullReg);
            rg_offset[t] <- replicateM(mkNullReg);
        end
    end

    RegFile#(Bit#(5), Bit#(8))     i_dc_val <- mkRegFile(0, fromInteger(16 * n_tables - 1));
    RegFile#(Bit#(9), Bit#(8))     i_ac_val <- mkRegFile(0, fromInteger(256 * n_tables - 1));
    RegFile#(Bit#(7), UInt#(8))    i_quant  <- mkRegFile(0, fromInteger(64 * n_tables - 1));
    RegFile#(Bit#(10), HuffLook_t) i_look   <- mkRegFile(0, fromInteger(512 * n_tables - 1));

    Reg#(Bool)          rg_ac   <- mkReg(False);
    Reg#(HuffTableId_t) rg_id   <- mkReg(0);
    Reg#(UInt#(4))      rg_len  <- mkReg(0);
    Reg#(UInt#(17))     rg_code <- mkReg(0);
    Reg#(Bit#(8))       rg_k    <- mkReg(0);

    //short code length counts and value total of the table being parsed, for the lookahead fill
    Vector#(HuffLookBits, Reg#(UInt#(8))) rg_counts <- replicateM(mkReg(0));
    Reg#(UInt#(9))                        rg_total  <- mkReg(0);

    //lookahead fill engine, fed by a request per table and the table values in order
    FIFOF#(LookFill_t) f_look_req   <- mkFIFOF1;
    FIFO#(Bit#(8))     f_look_val   <- mkFIFO;
    Reg#(Bool)         rg_lf_active <- mkReg(False);
    Reg#(LookFill_t)   rg_lf        <- mkRegU;
    Reg#(UInt#(9))     rg_lf_e      <- mkReg(0);
    Reg#(UInt#(5))     rg_lf_len    <- mkReg(0);
    Reg#(UInt#(8))     rg_lf_left   <- mkReg(0);
    Reg#(UInt#(9))     rg_lf_code   <- mkReg(0);
    Reg#(UInt#(9))     rg_lf_end    <- mkReg(0);
    Reg#(UInt#(9))     rg_lf_taken  <- mkReg(0);
    Reg#(Bool)         rg_lf_more   <- mkReg(False);

    Reg#(Maybe#(Tuple2#(Bit#(10), HuffLook_t))) rg_look_wr <- mkReg(tagged Invalid);

    //limit and offset of one code length, registered and then copied per table before they fan out
    RWire#(Tuple4#(Bit#(2), UInt#(4), UInt#(17), Bit#(8)))                w_commit    <- mkRWire;
    Reg#(Maybe#(Tuple4#(Bit#(2), UInt#(4), UInt#(17), Bit#(8))))          rg_commit   <- mkReg(tagged Invalid);
    Vector#(4, Reg#(Maybe#(Tuple3#(UInt#(4), UInt#(17), Bit#(8))))) rg_commit_t <- replicateM(mkReg(tagged Invalid));

    Wire#(HuffValIdx_t) w_hval_idx  <- mkWire;
    Wire#(QuantIdx_t)   w_quant_idx <- mkWire;

    function Bit#(1) eff_id(Bit#(1) id) = en_chroma ? id : 0;
    function Bit#(2) tbl_idx(Bool ac, HuffTableId_t id) = {pack(ac), eff_id(id)};

    //lookahead tables ordered {id, ac}, so a grayscale build stores only the first 512 entries
    function Bit#(10) look_addr(Bit#(2) t, Bit#(8) bits) = {t[0], t[1], bits};

    function Bit#(8) read_huff_val();
        let i = w_hval_idx;
        return i.ac ? i_ac_val.sub({eff_id(i.id), i.idx}) : i_dc_val.sub({eff_id(i.id), i.idx[3:0]});
    endfunction

    function UInt#(8) read_quant();
        return i_quant.sub({eff_id(w_quant_idx.tq), pack(w_quant_idx.k)});
    endfunction

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_route;
        for(Integer t = 0; t < 4; t = t + 1) begin
            Maybe#(Tuple3#(UInt#(4), UInt#(17), Bit#(8))) c = tagged Invalid;
            if(rg_commit matches tagged Valid {.ti, .l, .limit, .offset} &&& ti == fromInteger(t))
                c = tagged Valid tuple3(l, limit, offset);
            rg_commit_t[t] <= c;
        end
        rg_commit <= w_commit.wget;
    endrule

    for(Integer t = 0; t < 4; t = t + 1) begin
        (* fire_when_enabled, no_implicit_conditions *)
        rule r_commit (rg_commit_t[t] matches tagged Valid {.l, .limit, .offset});
            rg_limit[t][l]  <= limit;
            rg_offset[t][l] <= offset;
        endrule
    end

    //end of the entry range of a code, (code + 1) * 2^(HuffLookBits - len)
    function UInt#(9) code_range_end(UInt#(9) code, UInt#(5) len) = (code + 1) << (fromInteger(valueOf(HuffLookBits)) - len);

    if(en_look) begin
        rule r_look_start (!rg_lf_active);
            let r = f_look_req.first; f_look_req.deq;
            rg_lf         <= r;
            rg_lf_active  <= True;
            rg_lf_e       <= 0;
            rg_lf_len     <= 1;
            rg_lf_left    <= r.counts[0];
            rg_lf_code    <= 0;
            rg_lf_end     <= code_range_end(0, 1);
            rg_lf_taken   <= 0;
            rg_lf_more    <= r.total != 0;
        endrule

        //range ends and the values-left flag are registers, so each step only compares registers
        rule r_look_fill (rg_lf_active);
            Bit#(10) addr  = look_addr(rg_lf.tbl, pack(rg_lf_e)[7:0]);
            Bool     short = rg_lf_len <= fromInteger(valueOf(HuffLookBits)) && rg_lf_more;
            Maybe#(Tuple2#(Bit#(10), HuffLook_t)) wr = tagged Invalid;

            function Action take() = action
                f_look_val.deq;
                rg_lf_taken <= rg_lf_taken + 1;
                rg_lf_more  <= rg_lf_taken + 1 < rg_lf.total;
            endaction;

            if(short && rg_lf_left == 0) begin
                //no more codes of this length, move on to the next one
                UInt#(9) code = rg_lf_code << 1;
                rg_lf_len  <= rg_lf_len + 1;
                rg_lf_code <= code;
                rg_lf_end  <= code_range_end(code, rg_lf_len + 1);
                rg_lf_left <= rg_lf_len < fromInteger(valueOf(HuffLookBits)) ? rg_lf.counts[rg_lf_len] : 0;
            end else if(short) begin
                if(rg_lf_e < rg_lf_end) begin
                    Bit#(8) v = f_look_val.first;
                    wr = tagged Valid tuple2(addr, HuffLook_t {
                        valid: True,
                        len:   truncate(rg_lf_len),
                        used:  rg_lf_len + extend(unpack(v[3:0])),
                        sym:   v
                    });
                    rg_lf_e <= rg_lf_e + 1;
                end else begin
                    take;
                    rg_lf_code <= rg_lf_code + 1;
                    rg_lf_end  <= code_range_end(rg_lf_code + 1, rg_lf_len);
                    rg_lf_left <= rg_lf_left - 1;
                end
            end else begin
                //entries past the short codes stay invalid, values of longer codes are only drained
                if(rg_lf_e < 256) wr = tagged Valid tuple2(addr, unpack(0));
                rg_lf_e <= rg_lf_e < 256 ? rg_lf_e + 1 : 256;
                if(rg_lf_more) take;
                if(rg_lf_e == 256 && !rg_lf_more) rg_lf_active <= False;
            end
            rg_look_wr <= wr;
        endrule

        //lookahead writes are registered, so the LUTRAM write enable comes straight from a register
        (* fire_when_enabled, no_implicit_conditions *)
        rule r_look_write (rg_look_wr matches tagged Valid {.addr, .entry});
            i_look.upd(addr, entry);
        endrule
    end

    method Action write_quant(QuantTableId_t tq, UInt#(6) k, UInt#(8) q);
        i_quant.upd({eff_id(tq), pack(k)}, q);
    endmethod

    method Action huff_start(Bool ac, HuffTableId_t id);
        rg_ac    <= ac;
        rg_id    <= id;
        rg_len   <= 0;
        rg_code  <= 0;
        rg_k     <= 0;
        rg_total <= 0;
    endmethod

    method Action huff_count(UInt#(8) n);
        UInt#(17) code_end = rg_code + extend(n);
        w_commit.wset(tuple4(tbl_idx(rg_ac, rg_id), rg_len, code_end, rg_k - truncate(pack(rg_code))));
        rg_code <= code_end << 1;
        rg_k    <= rg_k + pack(n);
        rg_len  <= rg_len + 1;
        UInt#(9) total = rg_total + extend(n);
        rg_total <= total;
        if(en_look && rg_len < fromInteger(valueOf(HuffLookBits))) rg_counts[rg_len] <= n;
        if(en_look && rg_len == 15) f_look_req.enq(LookFill_t {
            tbl:    tbl_idx(rg_ac, rg_id),
            counts: readVReg(rg_counts),
            total:  total
        });
    endmethod

    method Action huff_value(UInt#(8) idx, Bit#(8) v);
        if(rg_ac) i_ac_val.upd({eff_id(rg_id), pack(idx)}, v);
        else if(idx < 16) i_dc_val.upd({eff_id(rg_id), pack(idx)[3:0]}, v);
        if(en_look) f_look_val.enq(v);
    endmethod

    method HuffLook_t huff_look(Bool ac, HuffTableId_t id, Bit#(HuffLookBits) bits);
        return en_look ? i_look.sub(look_addr(tbl_idx(ac, id), bits)) : unpack(0);
    endmethod

    method huff_busy = en_look && (rg_lf_active || f_look_req.notEmpty || isValid(rg_look_wr));

    method HuffLimits_t huff_limits(Bool ac, HuffTableId_t id);
        let t = tbl_idx(ac, id);
        return HuffLimits_t {
            limit:  readVReg(rg_limit[t]),
            offset: readVReg(rg_offset[t])
        };
    endmethod

    interface huff_val = toGPServer(asReg(w_hval_idx),  read_huff_val);
    interface quant    = toGPServer(asReg(w_quant_idx), read_quant);

endmodule

endpackage
