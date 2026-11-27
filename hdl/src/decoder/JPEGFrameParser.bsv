package JPEGFrameParser;

import DReg :: *;
import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import DecoderTypes :: *;
import DecTableStorage :: *;

interface JPEGFrameParser_ifc;
    interface Put#(SegByte_t)   seg;
    interface Get#(ScanCfg_t)   scan;
    interface Get#(FrameInfo_t) frame;

    method FrameInfo_t info;
    method Bool        scan_start;

    //one-cycle events: an error, and the parity of a frame the marker parser should drop
    method Maybe#(DecError_t) error;
    method Maybe#(Bit#(1))    skip_req;

    //the last coefficient of a scan has read its quantization table
    method Action scan_done;
endinterface

typedef enum { Hdr, Count, Val } TablePhase_t deriving(Bits, Eq, FShow);

//segment byte with its index positions decoded one stage ahead, at[i] means idx == i
typedef struct {
    SegByte_t        s;
    Vector#(6, Bool) at;
    Bool             at8;
    Bool             at9;
    Bool             at14;
} SegDec_t deriving(Bits, Eq, FShow);

/*
 * Second parser stage, the inverse of the encoder's framewriter. It reads the
 * payload bytes of DQT, DHT, SOF0/SOF1, SOS and DRI and programs the decoder
 * tables, the frame geometry and the scan configuration. The marker parser
 * tags every byte with its segment and index, and a classification stage
 * decodes the index positions the fields need, so each field is decoded from
 * registered flags and the table sub-states restart at index 0. Table writes
 * go to the table storage through its registered command queue.
 *
 * Supported is baseline sequential Huffman with 8-bit samples, one
 * interleaved scan of all components and no restart interval. A colour frame
 * has three components, the first with 1x1, 2x1 or 2x2 sampling (4:4:4,
 * 4:2:2, 4:2:0, at most max_sub) and the others with 1x1. A grayscale frame
 * has one component of any sampling. The scan configuration lists the blocks
 * of one MCU in decoding order, the luma blocks of an MCU row by row and then
 * one block per chroma component. Table ids beyond the stored tables are
 * skipped in DHT and DQT and rejected when a frame or scan references them.
 * With max_width > 0, wider frames are rejected.
 *
 * A rejected frame reports Unsupported and asks the marker parser to drop the
 * rest of the frame. Its remaining bytes are ignored up to the next Soi
 * token, and if its SOS still arrives the scan goes out marked as skip, so
 * the Huffman decoder drains the entropy-coded data. Every Soi token starts a
 * new frame with fresh frame state, while the tables stay as programmed.
 *
 * Tables of a new frame must not change while an earlier scan still reads
 * them. A Soi token therefore waits until every scan issued so far has passed
 * the quantization table read in the dequantizer, the last table read of a
 * scan. Header parsing of the next frame only waits for the tail of the
 * previous scan to pass the Huffman decoder, the RLD and that read.
 */
module mkJPEGFrameParser#(DecTableStorage_ifc tables, Bool en_chroma, ChromaSub_t max_sub, Integer max_width)(JPEGFrameParser_ifc);

    Integer n_tables = en_chroma ? 2 : 1;

    FIFO#(SegByte_t)   f_in    <- mkFIFO;
    FIFO#(SegDec_t)    f_dec   <- mkFIFO;
    FIFO#(ScanCfg_t)   f_scan  <- mkFIFO;
    FIFO#(FrameInfo_t) f_frame <- mkFIFO;

    //table segments
    Reg#(TablePhase_t)   rg_phase <- mkReg(Hdr);
    Reg#(UInt#(9))       rg_cnt   <- mkReg(0);
    Reg#(UInt#(9))       rg_total <- mkReg(0);
    Reg#(QuantTableId_t) rg_tq    <- mkReg(0);
    Reg#(Bool)           rg_skip  <- mkReg(False);

    //frame and scan
    Reg#(FrameInfo_t)                rg_info  <- mkReg(unpack(0));
    Reg#(Bool)                       rg_sof   <- mkReg(False);
    Reg#(UInt#(13))                  rg_mcu_w <- mkReg(0);
    Reg#(UInt#(13))                  rg_mcu_h <- mkReg(0);
    Vector#(3, Reg#(Bit#(8)))        rg_cid   <- replicateM(mkReg(0));

    //MCU grid for 8 and 16 pixel MCUs, and the sampling checks, registered as their bytes arrive
    Reg#(UInt#(13))   rg_w8   <- mkReg(0);
    Reg#(UInt#(13))   rg_w16  <- mkReg(0);
    Reg#(UInt#(13))   rg_h8   <- mkReg(0);
    Reg#(UInt#(13))   rg_h16  <- mkReg(0);
    Reg#(ChromaSub_t) rg_ysub <- mkReg(Sub444);
    Reg#(Bool)        rg_y_ok <- mkReg(False);
    Reg#(Bool)        rg_c_ok <- mkReg(False);
    Vector#(3, Reg#(QuantTableId_t)) rg_ctq   <- replicateM(mkReg(0));
    Vector#(3, Reg#(ScanBlock_t))    rg_scomp <- replicateM(mkReg(unpack(0)));

    //component and field position in the SOF component list and SOS selector list
    Reg#(UInt#(2)) rg_comp  <- mkReg(0);
    Reg#(UInt#(2)) rg_field <- mkReg(0);

    //the current frame was rejected, its bytes are dropped up to the next Soi token
    Reg#(Bool)    rg_bad <- mkReg(False);
    Reg#(Bit#(1)) rg_par <- mkReg(0);

    //scans issued whose last coefficient has not yet read its quantization table
    Reg#(UInt#(2)) rg_scans   <- mkReg(0);
    PulseWire      pw_issue   <- mkPulseWire;
    PulseWire      pw_retire  <- mkPulseWire;

    Reg#(Bool)               rg_scan  <- mkDReg(False);
    Reg#(Maybe#(DecError_t)) rg_error <- mkDReg(tagged Invalid);
    Reg#(Maybe#(Bit#(1)))    rg_drop  <- mkDReg(tagged Invalid);

    function Bool table_ok(Bit#(4) id) = id < fromInteger(n_tables);

    //the first rejection of a frame reports it and drops the rest of the frame
    function Action fail() = action
        if(!rg_bad) begin
            rg_error <= tagged Valid Unsupported;
            rg_drop  <= tagged Valid rg_par;
        end
        rg_bad <= True;
    endaction;

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_scans;
        rg_scans <= rg_scans + (pw_issue ? 1 : 0) - (pw_retire ? 1 : 0);
    endrule

    function Action dqt(SegDec_t d) = action
        let  s   = d.s;
        Bool hdr = d.at[0] || rg_phase == Hdr;
        Bool bad = False;
        if(hdr) begin
            rg_tq    <= truncate(s.data);
            rg_skip  <= !table_ok(s.data[3:0]);
            rg_cnt   <= 0;
            rg_phase <= Val;
            bad = s.data[7:4] != 0;
        end else begin
            if(!rg_skip) tables.cmd.put(tagged QuantWrite {
                tq: rg_tq,
                k:  truncate(rg_cnt),
                q:  unpack(s.data)
            });
            rg_cnt <= rg_cnt + 1;
            if(rg_cnt == 63) rg_phase <= Hdr;
        end
        if(bad) fail;
    endaction;

    //an ignored table is still walked but its counts and values land nowhere
    function Action dht(SegDec_t d) = action
        let          s     = d.s;
        TablePhase_t phase = d.at[0] ? Hdr : rg_phase;
        case(phase)
            Hdr: begin
                rg_skip  <= !table_ok(s.data[3:0]);
                tables.cmd.put(tagged HuffStart {
                    ac: s.data[4] == 1,
                    id: truncate(s.data)
                });
                rg_cnt   <= 0;
                rg_total <= 0;
                rg_phase <= Count;
                if(s.data[7:5] != 0) fail;
            end
            Count: begin
                UInt#(9) total = rg_total + extend(unpack(s.data));
                if(!rg_skip) tables.cmd.put(tagged HuffCount unpack(s.data));
                rg_total <= total;
                rg_cnt   <= rg_cnt == 15 ? 0 : rg_cnt + 1;
                if(rg_cnt == 15) rg_phase <= total == 0 ? Hdr : Val;
            end
            Val: begin
                if(!rg_skip) tables.cmd.put(tagged HuffValue {
                    idx: truncate(rg_cnt),
                    v:   s.data
                });
                rg_cnt <= rg_cnt + 1;
                if(rg_cnt + 1 == rg_total) rg_phase <= Hdr;
            end
        endcase
    endaction;

    function Action sof(SegDec_t d) = action
        let  s    = d.s;
        let  info = rg_info;
        Bool bad  = False;
        if(d.at[0])      bad = s.data != 8;
        else if(d.at[1]) info.height = unpack({s.data, 8'h00});
        else if(d.at[2]) info.height = rg_info.height | extend(unpack(s.data));
        else if(d.at[3]) info.width  = unpack({s.data, 8'h00});
        else if(d.at[4]) info.width  = rg_info.width | extend(unpack(s.data));
        else if(d.at[5]) begin
            info.ncomp = truncate(unpack(s.data));
            rg_comp    <= 0;
            rg_field   <= 0;
            rg_c_ok    <= True;
            rg_w8      <= truncate((rg_info.width + 7) >> 3);
            rg_w16     <= truncate((rg_info.width + 15) >> 4);
            rg_h8      <= truncate((rg_info.height + 7) >> 3);
            rg_h16     <= truncate((rg_info.height + 15) >> 4);
            bad = !(s.data == 1 || (en_chroma && s.data == 3))
               || rg_info.width == 0 || rg_info.height == 0
               || (max_width > 0 && rg_info.width > fromInteger(max_width));
        end else begin
            let c = rg_comp;
            case(rg_field)
                0: rg_cid[c] <= s.data;
                1: begin
                    //the first component sets the subsampling, the others must be 1x1
                    ChromaSub_t sub = s.data == 'h21 ? Sub422 : (s.data == 'h22 ? Sub420 : Sub444);
                    if(c == 0) begin
                        rg_ysub <= sub;
                        rg_y_ok <= (s.data == 'h11 || s.data == 'h21 || s.data == 'h22) && pack(sub) <= pack(max_sub);
                    end else if(s.data != 'h11) rg_c_ok <= False;
                end
                2: begin
                    rg_ctq[c] <= truncate(s.data);
                    bad = !table_ok(s.data[3:0]);
                end
            endcase
            rg_field <= rg_field == 2 ? 0 : rg_field + 1;
            if(rg_field == 2) rg_comp <= rg_comp + 1;
        end

        //the sampling checks of all components are registers by the last byte, which holds a table id
        if(s.last) begin
            Bool        gray = rg_info.ncomp == 1;
            ChromaSub_t sub  = gray ? Sub444 : rg_ysub;
            info.sub = sub;
            rg_mcu_w <= sub == Sub444 ? rg_w8 : rg_w16;
            rg_mcu_h <= sub == Sub420 ? rg_h16 : rg_h8;
            rg_sof   <= True;
            bad = bad || !(gray ? d.at8 : d.at14) || (!gray && !(rg_y_ok && rg_c_ok));
        end
        rg_info <= info;
        if(bad) fail;
    endaction;

    //blocks of one MCU in decoding order
    function Vector#(MaxMcuBlocks, ScanBlock_t) mcu_blocks();
        function ScanBlock_t blk(Integer c, Bit#(2) sub);
            ScanBlock_t b = rg_scomp[c];
            b.comp = fromInteger(c);
            b.sub  = sub;
            return b;
        endfunction
        Vector#(MaxMcuBlocks, ScanBlock_t) v = replicate(blk(0, 0));
        if(rg_info.ncomp == 3) case(rg_info.sub)
            Sub444: begin
                v[1] = blk(1, 0);
                v[2] = blk(2, 0);
            end
            Sub422: begin
                v[1] = blk(0, 1);
                v[2] = blk(1, 0);
                v[3] = blk(2, 0);
            end
            Sub420: begin
                v[1] = blk(0, 1);
                v[2] = blk(0, 2);
                v[3] = blk(0, 3);
                v[4] = blk(1, 0);
                v[5] = blk(2, 0);
            end
        endcase
        return v;
    endfunction

    function UInt#(3) mcu_blocks_m1();
        UInt#(3) n = 0;
        if(rg_info.ncomp == 3) case(rg_info.sub)
            Sub444: n = 2;
            Sub422: n = 3;
            Sub420: n = 5;
        endcase
        return n;
    endfunction

    function Action sos(SegDec_t d) = action
        let  s   = d.s;
        let  c   = rg_comp;
        Bool bad = False;
        if(d.at[0]) begin
            bad = !rg_sof || s.data != extend(pack(rg_info.ncomp));
            rg_comp  <= 0;
            rg_field <= 0;
        end else if(c < rg_info.ncomp) begin
            rg_field <= rg_field == 1 ? 0 : 1;
            if(rg_field == 1) rg_comp <= c + 1;
            if(rg_field == 0) begin
                //map the scan component selector to its frame component
                QuantTableId_t tq = 0;
                for(Integer i = 0; i < 3; i = i + 1)
                    if(rg_cid[i] == s.data) tq = rg_ctq[i];
                rg_scomp[c] <= ScanBlock_t {
                    comp: 0,
                    sub:  0,
                    tq:   tq,
                    td:   0,
                    ta:   0
                };
            end else begin
                let sc = rg_scomp[c];
                sc.td = truncate(s.data >> 4);
                sc.ta = truncate(s.data);
                rg_scomp[c] <= sc;
                bad = !table_ok(s.data[7:4]) || !table_ok(s.data[3:0]);
            end
        end
        if(s.last) begin
            //Ns selector pairs and three spectral bytes
            bad = bad || !(rg_info.ncomp == 1 ? d.at[5] : d.at9);
            Bool skip = bad || rg_bad;
            f_scan.enq(ScanCfg_t {
                skip:    skip,
                nblk_m1: mcu_blocks_m1,
                mcu_w:   rg_mcu_w,
                mcu_h:   rg_mcu_h,
                blocks:  mcu_blocks
            });
            if(!skip) begin
                f_frame.enq(rg_info);
                rg_scan <= True;
                pw_issue.send;
            end
        end
        if(bad) fail;
    endaction;

    //index positions decoded ahead, like the marker parser classifies bytes before its state machine
    rule r_classify;
        let s = f_in.first; f_in.deq;
        function Bool at(Integer i) = s.idx == fromInteger(i);
        f_dec.enq(SegDec_t {
            s:    s,
            at:   genWith(at),
            at8:  at(8),
            at9:  at(9),
            at14: at(14)
        });
    endrule

    //a new frame waits until no earlier scan reads the tables any more
    //the table command queue is checked for room up front, so its write needs no condition of its own
    rule r_segment ((f_dec.first.s.kind != Soi || rg_scans == 0) && tables.cmd_ready);
        let d = f_dec.first; f_dec.deq;
        let s = d.s;
        if(s.kind == Soi) begin
            rg_bad   <= False;
            rg_sof   <= False;
            rg_phase <= Hdr;
            rg_par   <= ~rg_par;
        end else if(rg_bad) begin
            //a rejected frame still drains its scan if the SOS got through
            if(s.kind == Sos && s.last) sos(d);
        end else case(s.kind)
            Dqt: dqt(d);
            Dht: dht(d);
            Sof: sof(d);
            Sos: sos(d);
            Dri: if(s.data != 0) fail;
        endcase
    endrule

    interface seg   = toPut(f_in);
    interface scan  = toGet(f_scan);
    interface frame = toGet(f_frame);

    method info       = rg_info;
    method scan_start = rg_scan;
    method error      = rg_error;
    method skip_req   = rg_drop;

    method Action scan_done;
        pw_retire.send;
    endmethod

endmodule

endpackage
