package HuffDecoder;

import FIFO :: *;
import FIFOF :: *;
import Vector :: *;
import GetPut :: *;
import ClientServer :: *;

import EncoderUtil :: *;
import DecoderTypes :: *;
import JPEGBitstreamDec :: *;

interface HuffDecoder_ifc;
    interface Put#(ScanCfg_t)                huff_scan;
    interface Get#(SymToken_t)               sym;
    interface Client#(HuffValIdx_t, Bit#(8)) huff_val;
    method Maybe#(DecError_t)                error;
endinterface

typedef enum { Idle, Look, Find, Read, Consume, Drain } HuffState_t deriving(Bits, Eq, FShow);

typedef struct {
    Bool     found;
    UInt#(5) len;
    Bit#(8)  idx;
} HuffMatch_t deriving(Bits, Eq, FShow);

//symbol as the loop leaves it, the token fields are derived one stage later
typedef struct {
    CoefPos_t pos;
    Bit#(8)   sym;
    Bit#(11)  raw;
    UInt#(7)  k;
    Bool      is_ac;
    Bool      first;
} HuffSym_t deriving(Bits, Eq, FShow);

//shortest code length whose LIMIT the top window bits stay below, len 0 if none
//LIMIT(l) left-aligned to 16 bits, LIMIT(l) * 2^(16 - l), is non-decreasing in l for canonical codes,
//so the matches form a thermometer and its edge is the code length
//the alignment is a static shift of the l + 1 significant bits, so each compare is only l + 1 bits wide
function HuffMatch_t huff_find(HuffLimits_t lim, Bit#(16) bits);
    Vector#(16, Bool)    match_l = newVector;
    Vector#(16, Bit#(8)) idx_l   = newVector;
    for(Integer l = 1; l <= 16; l = l + 1) begin
        Bit#(17) mask    = fromInteger(2 ** (l + 1) - 1);
        Bit#(17) aligned = (pack(lim.limit[l - 1]) & mask) << (16 - l);
        match_l[l - 1] = zeroExtend(bits) < aligned;
        idx_l[l - 1]   = truncate(bits >> (16 - l)) + lim.offset[l - 1];
    end

    Bit#(16) m     = pack(match_l);
    Bit#(16) first = m & ~(m << 1);
    //a code exists exactly when the 16-bit limit, the top of the thermometer, matches
    HuffMatch_t res = HuffMatch_t {
        found: m[15] == 1,
        len:   0,
        idx:   0
    };
    for(Integer l = 0; l < 16; l = l + 1) begin
        if(first[l] == 1) res.len = res.len | fromInteger(l + 1);
        if(first[l] == 1) res.idx = res.idx | idx_l[l];
    end
    return res;
endfunction

/*
 * Baseline Huffman symbol decoder for one interleaved scan, the inverse of
 * HuffEncoder. No LUTRAM read shares a cycle with the logic that computes its
 * address or with the logic that uses its data, like the encoder's registered
 * table lookups. Every symbol takes three cycles. With en_look, codes of up
 * to HuffLookBits bits, the common case, take two cycles and longer codes
 * four.
 *
 *   Look     only with en_look, lookahead table read with the registered top
 *            window bits and table selection, and the end-of-block and
 *            overflow test for every run length from rg_k. A hit registers
 *            code length and symbol and goes to Consume, a miss continues
 *            with Find.
 *   Find     the code length search over the registered limit set,
 *            registers code length and HUFFVAL address, and without en_look
 *            the end-of-block and overflow test
 *   Read     HUFFVAL read into rg_sym, the window drops the code bits
 *   Consume  magnitude bits taken after the code bits, window shifted by
 *            the remaining code length and the magnitude size, next state
 *            chosen from candidates that were computed from registers
 *
 * Token fields that do not feed back into the loop, such as the coefficient
 * index, follow in r_token after the loop's output FIFO.
 *
 * The output carries raw magnitude bits, sign extension and DC prediction
 * follow in mkRLD. The first symbol of a scan is flagged so mkRLD resets its
 * predictors in band.
 */
module mkHuffDecoder#(
    JPEGBitstreamDec_ifc bits,
    function HuffLimits_t limits(Bool ac, HuffTableId_t id),
    function HuffLook_t look(Bool ac, HuffTableId_t id, Bit#(HuffLookBits) b),
    Bool tables_busy,
    Bool en_look
)(HuffDecoder_ifc);

    HuffState_t first_state = en_look ? Look : Find;

    FIFO#(ScanCfg_t)    f_scan <- mkFIFO;
    FIFOF#(HuffSym_t)   f_sym  <- mkGFIFOF(True, False);
    FIFO#(SymToken_t)   f_out  <- mkFIFO;

    Reg#(HuffState_t) rg_state <- mkReg(Idle);
    Reg#(ScanCfg_t)   rg_cfg   <- mkRegU;

    //table read client, registered address and same-cycle response
    Reg#(HuffValIdx_t) rg_req  <- mkRegU;
    Wire#(Bit#(8))     w_resp  <- mkDWire(?);
    Reg#(UInt#(5))     rg_len  <- mkRegU;
    Reg#(Bit#(8))      rg_sym  <- mkRegU;

    //code bits still in the window when Consume starts, the full length after a lookahead hit and 0 after Read,
    //and the bits Consume drops, those code bits plus the magnitude size
    Reg#(UInt#(5))     rg_code_left <- mkRegU;
    Reg#(UInt#(6))     rg_used      <- mkRegU;

    //scan position, with flags precomputed whenever the position changes
    Reg#(UInt#(2))  rg_comp      <- mkReg(0);
    Reg#(UInt#(7))  rg_k         <- mkReg(0);
    Reg#(UInt#(13)) rg_mcu_x     <- mkReg(0);
    Reg#(UInt#(13)) rg_mcu_y     <- mkReg(0);
    Reg#(Bool)      rg_comp_last <- mkReg(False);
    Reg#(Bool)      rg_x_last    <- mkReg(False);
    Reg#(Bool)      rg_y_last    <- mkReg(False);

    //MCU grid size minus two, the next position is the last one when the current one equals it
    Reg#(UInt#(13)) rg_w_m2      <- mkReg(0);
    Reg#(UInt#(13)) rg_h_m2      <- mkReg(0);
    Reg#(Bool)      rg_first     <- mkReg(False);

    //per run length r, whether the coefficient lands on index 63 or beyond it, from rg_k during Find
    Reg#(Vector#(16, Bool)) rg_end_r <- mkRegU;
    Reg#(Vector#(16, Bool)) rg_ovf_r <- mkRegU;

    //table selection for the next Find and its limit set
    Reg#(Bool)          rg_sel_ac <- mkReg(False);
    Reg#(HuffTableId_t) rg_sel_id <- mkReg(0);
    Reg#(HuffLimits_t)  rg_lim    <- mkRegU;

    Reg#(Maybe#(DecError_t)) rg_error <- mkReg(tagged Invalid);

    rule r_start (rg_state == Idle && !bits.draining && !tables_busy);
        let cfg = f_scan.first; f_scan.deq;
        rg_cfg       <= cfg;
        rg_comp      <= 0;
        rg_k         <= 0;
        rg_mcu_x     <= 0;
        rg_mcu_y     <= 0;
        rg_comp_last <= cfg.ncomp == 1;
        rg_x_last    <= cfg.mcu_w == 1;
        rg_y_last    <= cfg.mcu_h == 1;
        rg_w_m2      <= cfg.mcu_w - 2;
        rg_h_m2      <= cfg.mcu_h - 2;
        rg_first     <= True;
        rg_sel_ac    <= False;
        rg_sel_id    <= cfg.comps[0].td;
        rg_lim       <= limits(False, cfg.comps[0].td);
        rg_state     <= first_state;
    endrule

    function Bool lands_on_end(Integer r) = rg_k + fromInteger(r) == 63;
    function Bool lands_beyond(Integer r) = rg_k + fromInteger(r) > 63;

    if(en_look) begin
        rule r_look (rg_state == Look && bits.ready);
            let e = look(rg_sel_ac, rg_sel_id, bits.window[47:48 - valueOf(HuffLookBits)]);

            rg_end_r <= genWith(lands_on_end);
            rg_ovf_r <= genWith(lands_beyond);

            rg_sym       <= e.sym;
            rg_code_left <= extend(e.len);
            rg_used      <= extend(e.used);
            rg_state     <= e.valid ? Consume : Find;
        endrule
    end

    rule r_find (rg_state == Find && (en_look || bits.ready));
        let m = huff_find(rg_lim, bits.window[47:32]);
        if(!en_look) begin
            rg_end_r <= genWith(lands_on_end);
            rg_ovf_r <= genWith(lands_beyond);
        end
        rg_req <= HuffValIdx_t {
            ac:  rg_sel_ac,
            id:  rg_sel_id,
            idx: m.idx
        };
        rg_len <= m.len;

        if(!m.found) begin
            rg_error <= tagged Valid BadHuffCode;
            rg_state <= Drain;
        end else begin
            rg_state <= Read;
        end
    endrule

    //HUFFVAL read into a register while the window drops the code bits
    rule r_read (rg_state == Read);
        rg_sym       <= w_resp;
        rg_code_left <= 0;
        rg_used      <= extend(unpack(w_resp[3:0]));
        bits.consume(extend(rg_len));
        rg_state     <= Consume;
    endrule

    rule r_consume (rg_state == Consume && f_sym.notFull);
        Bit#(8)  sym   = rg_sym;
        UInt#(4) r     = unpack(sym[7:4]);
        UInt#(4) s     = unpack(sym[3:0]);
        Bool     is_ac = rg_sel_ac;

        //candidate positions from registers only
        UInt#(2)   comp_next = rg_comp_last ? 0 : rg_comp + 1;
        UInt#(13)  x_next    = rg_x_last ? 0 : rg_mcu_x + 1;
        UInt#(13)  y_next    = rg_mcu_y + 1;
        Bool       mcu_last  = rg_comp_last && rg_x_last && rg_y_last;
        ScanComp_t sc        = rg_cfg.comps[rg_comp];
        ScanComp_t sc_next   = rg_cfg.comps[comp_next];

        //a zero run of 16 (r 15, s 0) is only visible when it closes the block
        Bool     eob       = is_ac && s == 0 && r != 15;
        Bool     zrl       = is_ac && s == 0 && r == 15;
        Bool     block_end = eob || (is_ac && rg_end_r[r]);
        Bool     overflow  = is_ac && !eob && rg_ovf_r[r];
        Bool     emit      = !zrl || block_end;
        UInt#(7) k_next    = is_ac ? rg_k + extend(r) + 1 : 1;

        bits.consume(rg_used);

        //the next limit set, both candidates are selected by registers and only the final choice
        //waits for the symbol, overflow is ignored because it drains the scan
        rg_lim <= block_end ? limits(False, sc_next.td) : limits(True, sc.ta);

        if(overflow) begin
            rg_error <= tagged Valid CoefOverflow;
            rg_state <= Drain;
        end else begin
            if(emit) f_sym.enq(HuffSym_t {
                pos: CoefPos_t {
                    tq:         sc.tq,
                    comp:       pack(rg_comp),
                    k:          ?,
                    last:       block_end,
                    mcu_end:    block_end && rg_comp_last,
                    last_block: block_end && mcu_last
                },
                sym:   sym,
                raw:   (bits.window << rg_code_left)[47:37],
                k:     rg_k,
                is_ac: is_ac,
                first: rg_first
            });
            if(emit) rg_first <= False;

            rg_k      <= block_end ? 0 : k_next;
            rg_sel_ac <= !block_end;
            rg_sel_id <= block_end ? sc_next.td : sc.ta;
            if(block_end) begin
                rg_comp      <= comp_next;
                rg_comp_last <= comp_next + 1 == rg_cfg.ncomp;
                if(rg_comp_last) begin
                    rg_mcu_x  <= x_next;
                    rg_x_last <= rg_x_last ? rg_cfg.mcu_w == 1 : rg_mcu_x == rg_w_m2;
                    if(rg_x_last) begin
                        rg_mcu_y  <= y_next;
                        rg_y_last <= rg_mcu_y == rg_h_m2;
                    end
                end
            end
            rg_state <= block_end && mcu_last ? Drain : first_state;
        end
    endrule

    //token fields that do not feed back into the loop
    rule r_token;
        let      h = f_sym.first; f_sym.deq;
        UInt#(4) r = unpack(h.sym[7:4]);
        UInt#(4) s = unpack(h.sym[3:0]);
        let pos = h.pos;
        pos.k = h.is_ac ? truncate(h.k + extend(r)) : 0;
        f_out.enq(SymToken_t {
            pos:     pos,
            raw:     h.raw,
            s:       s,
            is_dc:   !h.is_ac,
            first:   h.first,
            has_val: !h.is_ac || s != 0
        });
    endrule

    rule r_drain (rg_state == Drain);
        bits.drain;
        rg_state <= Idle;
    endrule

    interface huff_scan = toPut(f_scan);
    interface sym       = toGet(f_out);
    interface huff_val  = toGPClient(rg_req, asReg(w_resp));

    method error = rg_error;

endmodule

endpackage
