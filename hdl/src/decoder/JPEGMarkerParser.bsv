package JPEGMarkerParser;

import FIFO :: *;
import FIFOF :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import DecoderTypes :: *;

interface JPEGMarkerParser_ifc;
    interface Put#(Bit#(8))    bytes;
    interface Get#(SegByte_t)  seg;
    interface Get#(EcsToken_t) ecs;
    method Maybe#(DecError_t)  error;
endinterface

//byte properties the state machine needs, registered one stage ahead
typedef struct {
    Bit#(8)           data;
    Bool              is_ff;
    Bool              is_zero;
    Bool              is_rst;
    Bool              is_soi;
    Bool              no_length;
    Maybe#(SegKind_t) parsed;
    Bool              bad_sof;
} MarkerByte_t deriving(Bits, Eq, FShow);

typedef enum {
    MarkerFF,
    MarkerCode,
    LenHi,
    LenLo,
    Payload,
    Ecs,
    Halt
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
 * dropped here, unsupported SOF types and restart markers stop the stream.
 * After a SOS payload the stage switches to the entropy-coded segment. Byte
 * classification (marker codes, 0xFF, stuffing zero) is registered one stage
 * ahead of the state machine.
 */
module mkJPEGMarkerParser(JPEGMarkerParser_ifc);

    FIFO#(Bit#(8))      f_in  <- mkBypassFIFO;
    FIFO#(MarkerByte_t) f_cls <- mkFIFO;
    FIFO#(SegByte_t)    f_seg <- mkFIFO;
    FIFO#(EcsToken_t) f_ecs <- mkFIFO;

    Reg#(MarkerState_t)     rg_state <- mkReg(MarkerFF);
    Reg#(Bool)              rg_soi   <- mkReg(False);
    Reg#(Maybe#(SegKind_t)) rg_seg   <- mkReg(tagged Invalid);
    Reg#(UInt#(16))         rg_len   <- mkReg(0);
    Reg#(UInt#(5))          rg_idx   <- mkReg(0);
    Reg#(Bool)              rg_ff    <- mkReg(False);

    Reg#(Maybe#(DecError_t)) rg_error <- mkReg(tagged Invalid);

    //state after a marker code, markers without a length field are SOI, EOI, TEM and RSTn
    function MarkerState_t on_marker(MarkerByte_t m);
        MarkerState_t n = LenHi;
        if(m.is_ff) n = MarkerCode;
        else if(m.no_length) n = MarkerFF;
        return n;
    endfunction

    function Action marker(MarkerByte_t m) = action
        rg_seg <= m.parsed;
    endaction;

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
            no_length: b == 'hD8 || b == 'hD9 || b == 'h01 || rst,
            parsed:    parsed_segment(b),
            bad_sof:   is_unsupported_sof(b)
        });
    endrule

    rule r_byte;
        let m = f_cls.first; f_cls.deq;
        let b = m.data;

        MarkerState_t      next = rg_state;
        Maybe#(DecError_t) err  = tagged Invalid;

        case(rg_state)
            MarkerFF: begin
                if(m.is_ff) next = MarkerCode;
                else if(!rg_soi) err = tagged Valid MissingSoi;
            end
            MarkerCode: begin
                next = on_marker(m);
                marker(m);
                if(m.is_soi) rg_soi <= True;
                if(!rg_soi && !m.is_soi && !m.is_ff) err = tagged Valid MissingSoi;
                if(m.bad_sof) err = tagged Valid Unsupported;
            end
            LenHi: begin
                rg_len <= unpack({b, 8'h00});
                next   = LenLo;
            end
            LenLo: begin
                UInt#(16) l = (rg_len | extend(unpack(b))) - 2;
                rg_len <= l;
                rg_idx <= 0;
                next   = l == 0 ? MarkerFF : Payload;
            end
            Payload: begin
                Bool last = rg_len == 1;
                if(rg_seg matches tagged Valid .k) f_seg.enq(SegByte_t {
                    kind: k,
                    idx:  rg_idx,
                    last: last,
                    data: b
                });
                rg_len <= rg_len - 1;
                rg_idx <= rg_idx == 31 ? 31 : rg_idx + 1;
                rg_ff  <= False;
                if(last) next = rg_seg == tagged Valid Sos ? Ecs : MarkerFF;
            end
            Ecs: begin
                if(rg_ff) begin
                    if(m.is_zero) begin
                        f_ecs.enq(tagged Byte 'hFF);
                        rg_ff <= False;
                    end else if(m.is_rst) begin
                        err = tagged Valid Unsupported;
                    end else if(!m.is_ff) begin
                        f_ecs.enq(tagged End);
                        rg_ff <= False;
                        next  = on_marker(m);
                        marker(m);
                        if(m.bad_sof) err = tagged Valid Unsupported;
                    end
                end else if(m.is_ff) begin
                    rg_ff <= True;
                end else begin
                    f_ecs.enq(tagged Byte b);
                end
            end
            Halt: noAction;
        endcase

        if(isValid(err)) begin
            if(!isValid(rg_error)) rg_error <= err;
            next = Halt;
        end
        rg_state <= next;
    endrule

    interface bytes = toPut(f_in);
    interface seg   = toGet(f_seg);
    interface ecs   = toGet(f_ecs);

    method error = rg_error;

endmodule

endpackage
