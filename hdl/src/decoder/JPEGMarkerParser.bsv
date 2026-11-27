package JPEGMarkerParser;

import DReg :: *;
import FIFO :: *;
import FIFOF :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import DecoderTypes :: *;

interface JPEGMarkerParser_ifc;
    interface Put#(Bit#(8))    bytes;
    interface Get#(SegByte_t)  seg;
    interface Get#(EcsToken_t) ecs;

    //drop the rest of the frame with this frame parity, see mkJPEGFrameParser
    method Action skip(Bit#(1) parity);

    //one-cycle error event
    method Maybe#(DecError_t) error;
endinterface

//byte properties the state machine needs, registered one stage ahead
typedef struct {
    Bit#(8)           data;
    Bool              is_ff;
    Bool              is_zero;
    Bool              is_rst;
    Bool              is_soi;
    Bool              is_eoi;
    Bool              no_length;
    Maybe#(SegKind_t) parsed;
    Bool              bad_sof;
} MarkerByte_t deriving(Bits, Eq, FShow);

typedef enum {
    Hunt,
    MarkerFF,
    MarkerCode,
    LenHi,
    LenLo,
    Payload,
    Ecs
} MarkerState_t deriving(Bits, Eq, FShow);

//segments the frame parser interprets, everything else is skipped here
function Maybe#(SegKind_t) parsed_segment(Bit#(8) m);
    case(m)
        'hDB:       return tagged Valid Dqt;
        'hC4:       return tagged Valid Dht;
        'hC0, 'hC1: return tagged Valid Sof;
        'hDA:       return tagged Valid Sos;
        'hDD:       return tagged Valid Dri;
        default:    return tagged Invalid;
    endcase
endfunction

function Bool is_unsupported_sof(Bit#(8) m) =
    m >= 'hC2 && m <= 'hCF && m != 'hC4 && m != 'hC8 && m != 'hCC;

/*
 * First parser stage, the byte-level framing of a JFIF stream. It splits the
 * stream into header segment payloads for the frame parser, tagged with their
 * marker and byte index, and the entropy-coded segment for the bit reader,
 * with stuffed zero bytes removed and closed by an End token at the next
 * marker. Segments the decoder does not use (APPn, COM and others) are
 * dropped here. Byte classification (marker codes, 0xFF, stuffing zero) is
 * registered one stage ahead of the state machine.
 *
 * Outside a frame the stage hunts for SOI and ignores everything else, so
 * padding before, between and after frames needs no special handling. Each
 * SOI sends a Soi token to the frame parser and toggles the frame parity. A
 * frame ends at its EOI. Anything else that breaks the frame structure
 * reports an error and recovers:
 *
 *   unsupported SOF type, restart marker   Unsupported, hunt for the next SOI
 *   a non-marker byte where a marker
 *   belongs, a length below 2, another
 *   marker ending the entropy-coded data   BadMarker, hunt for the next SOI
 *   SOI inside a frame                     BadMarker, the new frame starts
 *
 * An entropy-coded segment always ends with an End token, so the Huffman
 * decoder conceals whatever the segment lacks. skip() comes from the frame
 * parser when it rejects a header. It applies only while the frame with that
 * parity is still being parsed, so a late request never hits the next frame.
 */
module mkJPEGMarkerParser(JPEGMarkerParser_ifc);

    FIFO#(Bit#(8))      f_in  <- mkBypassFIFO;
    FIFO#(MarkerByte_t) f_cls <- mkFIFO;
    FIFO#(SegByte_t)    f_seg <- mkFIFO;
    FIFO#(EcsToken_t)   f_ecs <- mkFIFO;

    Reg#(MarkerState_t)     rg_state <- mkReg(Hunt);
    Reg#(Maybe#(SegKind_t)) rg_seg   <- mkReg(tagged Invalid);
    Reg#(UInt#(16))         rg_len   <- mkReg(0);
    Reg#(UInt#(5))          rg_idx   <- mkReg(0);
    Reg#(Bool)              rg_ff    <- mkReg(False);
    Reg#(Bit#(1))           rg_par   <- mkReg(0);

    //pending skip request of the frame parser
    //pending skip request of the frame parser, matched against the frame parity when it arrives
    RWire#(Bit#(1)) w_skip        <- mkRWire;
    Reg#(Bool)      rg_skip       <- mkReg(False);
    PulseWire       pw_skip_taken <- mkPulseWire;
    PulseWire       pw_soi        <- mkPulseWire;

    Reg#(Maybe#(DecError_t)) rg_error <- mkDReg(tagged Invalid);

    //the frame parity toggles here at each SOI of r_byte, so r_byte only reads registers of this rule
    //a request that arrives with an SOI belongs to the frame that SOI ends
    (* fire_when_enabled, no_implicit_conditions *)
    rule r_skip;
        if(pw_soi) rg_par <= ~rg_par;
        if(w_skip.wget matches tagged Valid .p) rg_skip <= p == rg_par && !pw_soi;
        else if(pw_skip_taken)                  rg_skip <= False;
    endrule

    //classify each byte before the variable state machine sees it
    rule r_classify;
        let b = f_in.first; f_in.deq;
        Bool rst = b >= 'hD0 && b <= 'hD7;
        f_cls.enq(MarkerByte_t {
            data:      b,
            is_ff:     b == 'hFF,
            is_zero:   b == 'h00,
            is_rst:    rst,
            is_soi:    b == 'hD8,
            is_eoi:    b == 'hD9,
            no_length: b == 'hD8 || b == 'hD9 || b == 'h01 || rst,
            parsed:    parsed_segment(b),
            bad_sof:   is_unsupported_sof(b)
        });
    endrule

    //a skip request for the current frame takes a cycle of its own ahead of the next byte,
    //so the byte datapath does not depend on it
    rule r_drop (rg_skip);
        pw_skip_taken.send;
        if(rg_state == Ecs) f_ecs.enq(tagged End);
        if(rg_state != Hunt) begin
            rg_state <= Hunt;
            rg_ff    <= False;
        end
    endrule

    rule r_byte (!rg_skip);
        let m = f_cls.first; f_cls.deq;
        let b = m.data;

        MarkerState_t      next  = rg_state;
        Bool               ff    = rg_ff;
        Bool               soi   = False;
        Maybe#(DecError_t) err   = tagged Invalid;
        Maybe#(SegByte_t)  seg   = tagged Invalid;
        Maybe#(EcsToken_t) tok   = tagged Invalid;

        case(rg_state)
            Hunt: begin
                if(ff && m.is_soi) begin
                    soi  = True;
                    next = MarkerFF;
                end
                ff = m.is_ff;
            end
            MarkerFF: begin
                if(m.is_ff) next = MarkerCode;
                else begin
                    err  = tagged Valid BadMarker;
                    next = Hunt;
                end
            end
            MarkerCode: begin
                rg_seg <= m.parsed;
                if(m.is_ff) next = MarkerCode;
                else if(m.is_soi) begin
                    err  = tagged Valid BadMarker;
                    soi  = True;
                    next = MarkerFF;
                end else if(m.is_eoi) next = Hunt;
                else if(m.bad_sof) begin
                    err  = tagged Valid Unsupported;
                    next = Hunt;
                end else if(m.is_rst) begin
                    err  = tagged Valid BadMarker;
                    next = Hunt;
                end else if(m.no_length) next = MarkerFF;
                else next = LenHi;
            end
            LenHi: begin
                rg_len <= unpack({b, 8'h00});
                next   = LenLo;
            end
            LenLo: begin
                UInt#(16) l = rg_len | extend(unpack(b));
                rg_len <= l - 2;
                rg_idx <= 0;
                if(l < 2) begin
                    err  = tagged Valid BadMarker;
                    next = Hunt;
                end else next = l == 2 ? MarkerFF : Payload;
            end
            Payload: begin
                Bool last = rg_len == 1;
                if(rg_seg matches tagged Valid .k) seg = tagged Valid SegByte_t {
                    kind: k,
                    idx:  rg_idx,
                    last: last,
                    data: b
                };
                rg_len <= rg_len - 1;
                rg_idx <= rg_idx == 31 ? 31 : rg_idx + 1;
                ff     = False;
                if(last) next = rg_seg == tagged Valid Sos ? Ecs : MarkerFF;
            end
            Ecs: begin
                if(ff) begin
                    if(m.is_zero) begin
                        tok = tagged Valid tagged Byte 'hFF;
                        ff = False;
                    end else if(!m.is_ff) begin
                        //any marker ends the segment, only EOI ends the frame cleanly
                        tok  = tagged Valid End;
                        ff   = False;
                        next = Hunt;
                        if(m.is_soi) begin
                            err  = tagged Valid BadMarker;
                            soi  = True;
                            next = MarkerFF;
                        end else if(m.is_rst) err = tagged Valid Unsupported;
                        else if(!m.is_eoi)    err = tagged Valid BadMarker;
                    end
                end else if(m.is_ff) begin
                    ff = True;
                end else begin
                    tok = tagged Valid tagged Byte b;
                end
            end
        endcase

        if(soi) begin
            seg = tagged Valid SegByte_t {
                kind: Soi,
                idx:  0,
                last: True,
                data: 0
            };
            pw_soi.send;
        end

        if(seg matches tagged Valid .x) f_seg.enq(x);
        if(tok matches tagged Valid .x) f_ecs.enq(x);

        rg_error <= err;
        rg_ff    <= ff;
        rg_state <= next;
    endrule

    interface bytes = toPut(f_in);
    interface seg   = toGet(f_seg);
    interface ecs   = toGet(f_ecs);

    method Action skip(Bit#(1) parity);
        w_skip.wset(parity);
    endmethod

    method error = rg_error;

endmodule

endpackage
