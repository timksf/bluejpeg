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

    method FrameInfo_t        info;
    method Bool               scan_start;
    method Maybe#(DecError_t) error;
endinterface

typedef enum { Hdr, Count, Val } TablePhase_t deriving(Bits, Eq, FShow);

/*
 * Second parser stage, the inverse of the encoder's framewriter. It reads the
 * payload bytes of DQT, DHT, SOF0/SOF1, SOS and DRI and programs the decoder
 * tables, the frame geometry and the scan configuration. The marker parser
 * tags every byte with its segment and index, so each field is decoded from
 * registered values and the table sub-states restart at index 0.
 *
 * Supported is baseline sequential Huffman with 8-bit samples, one
 * interleaved scan and no restart interval, with three 1x1 components
 * (en_chroma) or one component. Table ids beyond the stored tables are
 * skipped in DHT and DQT and rejected when a frame or scan references them.
 * With max_width > 0, wider frames are rejected. An error stops the stage.
 */
module mkJPEGFrameParser#(DecTableStorage_ifc tables, Bool en_chroma, Integer max_width)(JPEGFrameParser_ifc);

    Integer n_tables = en_chroma ? 2 : 1;

    FIFO#(SegByte_t)   f_in    <- mkFIFO;
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
    Reg#(UInt#(13))                  rg_mcu_w <- mkReg(0);
    Reg#(UInt#(13))                  rg_mcu_h <- mkReg(0);
    Vector#(3, Reg#(Bit#(8)))        rg_cid   <- replicateM(mkReg(0));
    Vector#(3, Reg#(QuantTableId_t)) rg_ctq   <- replicateM(mkReg(0));
    Vector#(3, Reg#(ScanComp_t))     rg_scomp <- replicateM(mkReg(unpack(0)));

    //component and field position in the SOF component list and SOS selector list
    Reg#(UInt#(2)) rg_comp  <- mkReg(0);
    Reg#(UInt#(2)) rg_field <- mkReg(0);

    Reg#(Bool)               rg_scan  <- mkDReg(False);
    Reg#(Maybe#(DecError_t)) rg_error <- mkReg(tagged Invalid);

    function Bool table_ok(Bit#(4) id) = id < fromInteger(n_tables);

    function Action fail() = action
        if(!isValid(rg_error)) rg_error <= tagged Valid Unsupported;
    endaction;

    function Action dqt(SegByte_t s) = action
        Bool hdr = s.idx == 0 || rg_phase == Hdr;
        Bool bad = False;
        if(hdr) begin
            rg_tq    <= truncate(s.data);
            rg_skip  <= !table_ok(s.data[3:0]);
            rg_cnt   <= 0;
            rg_phase <= Val;
            bad = s.data[7:4] != 0;
        end else begin
            if(!rg_skip) tables.write_quant(rg_tq, truncate(rg_cnt), unpack(s.data));
            rg_cnt <= rg_cnt + 1;
            if(rg_cnt == 63) rg_phase <= Hdr;
        end
        if(bad) fail;
    endaction;

    //an ignored table is still walked but its counts and values land nowhere
    function Action dht(SegByte_t s) = action
        TablePhase_t phase = s.idx == 0 ? Hdr : rg_phase;
        case(phase)
            Hdr: begin
                rg_skip  <= !table_ok(s.data[3:0]);
                tables.huff_start(s.data[4] == 1, truncate(s.data));
                rg_cnt   <= 0;
                rg_total <= 0;
                rg_phase <= Count;
                if(s.data[7:5] != 0) fail;
            end
            Count: begin
                UInt#(9) total = rg_total + extend(unpack(s.data));
                if(!rg_skip) tables.huff_count(unpack(s.data));
                rg_total <= total;
                rg_cnt   <= rg_cnt == 15 ? 0 : rg_cnt + 1;
                if(rg_cnt == 15) rg_phase <= total == 0 ? Hdr : Val;
            end
            Val: begin
                if(!rg_skip) tables.huff_value(truncate(rg_cnt), s.data);
                rg_cnt <= rg_cnt + 1;
                if(rg_cnt + 1 == rg_total) rg_phase <= Hdr;
            end
        endcase
    endaction;

    function Action sof(SegByte_t s) = action
        let  info = rg_info;
        Bool bad  = False;
        case(s.idx)
            0: bad = s.data != 8;
            1: info.height = unpack({s.data, 8'h00});
            2: info.height = rg_info.height | extend(unpack(s.data));
            3: info.width  = unpack({s.data, 8'h00});
            4: info.width  = rg_info.width | extend(unpack(s.data));
            5: begin
                info.ncomp = truncate(unpack(s.data));
                rg_comp    <= 0;
                rg_field   <= 0;
                rg_mcu_w   <= truncate((rg_info.width + 7) >> 3);
                rg_mcu_h   <= truncate((rg_info.height + 7) >> 3);
                bad = !(s.data == 1 || (en_chroma && s.data == 3))
                   || rg_info.width == 0 || rg_info.height == 0
                   || (max_width > 0 && rg_info.width > fromInteger(max_width));
            end
            default: begin
                let c = rg_comp;
                case(rg_field)
                    0: rg_cid[c] <= s.data;
                    1: bad = rg_info.ncomp == 3 && s.data != 'h11;
                    2: begin
                        rg_ctq[c] <= truncate(s.data);
                        bad = !table_ok(s.data[3:0]);
                    end
                endcase
                rg_field <= rg_field == 2 ? 0 : rg_field + 1;
                if(rg_field == 2) rg_comp <= rg_comp + 1;
            end
        endcase
        rg_info <= info;
        if(bad) fail;
    endaction;

    function Action sos(SegByte_t s) = action
        let  c   = rg_comp;
        Bool bad = False;
        if(s.idx == 0) begin
            bad = s.data != extend(pack(rg_info.ncomp));
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
                rg_scomp[c] <= ScanComp_t {
                    tq: tq,
                    td: 0,
                    ta: 0
                };
            end else begin
                let sc = rg_scomp[c];
                sc.td = truncate(s.data >> 4);
                sc.ta = truncate(s.data);
                rg_scomp[c] <= sc;
                bad = !table_ok(s.data[7:4]) || !table_ok(s.data[3:0]);
            end
        end
        if(bad) fail;
        if(s.last) begin
            f_scan.enq(ScanCfg_t {
                ncomp: rg_info.ncomp,
                mcu_w: rg_mcu_w,
                mcu_h: rg_mcu_h,
                comps: readVReg(rg_scomp)
            });
            f_frame.enq(rg_info);
            rg_scan <= True;
        end
    endaction;

    rule r_segment (!isValid(rg_error));
        let s = f_in.first; f_in.deq;
        case(s.kind)
            Dqt: dqt(s);
            Dht: dht(s);
            Sof: sof(s);
            Sos: sos(s);
            Dri: if(s.data != 0) fail;
        endcase
    endrule

    //after an error the remaining payload is dropped
    rule r_halt (isValid(rg_error));
        f_in.deq;
    endrule

    interface seg   = toPut(f_in);
    interface scan  = toGet(f_scan);
    interface frame = toGet(f_frame);

    method info       = rg_info;
    method scan_start = rg_scan;
    method error      = rg_error;

endmodule

endpackage
