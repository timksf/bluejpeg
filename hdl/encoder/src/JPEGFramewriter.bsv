package JPEGFramewriter;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import BuildVector :: *;
import ClientServer :: *;
import SpecialFIFOs :: *;

import Types :: *;
import ZigZag :: *;

//Complements encoded scan data with all markers and tables required for a
//JPEG/JFIF compliant image:
//  SOI -> APP0 -> DQT×(1|2) -> SOF0 -> DHT×(2|4) -> SOS -> scan data -> EOI
//
//Scan data arrives via scan_data Put as Maybe#(Bit#(8)):
//  tagged Valid byte  -  scan data byte (already byte-stuffed)
//  tagged Invalid     -  end-of-scan signal
//
//DQT and DHT table contents are read combinationally from TableStorage

typedef enum {
    IDLE,
    STATIC_HEADER,
    DQT_HEAD,
    DQT_DATA,
    DHT_SUM,
    DHT_HEAD,
    DHT_BITS,
    DHT_VAL,
    SOF0,
    SCAN_HEAD,
    SCAN,
    EOI,
    DONE
} State_t deriving(Eq, Bits, FShow);

function HuffTableType_t dht_htt(Bit#(2) tbl);
    return case (tbl)
        0: DC_Luma;
        1: AC_Luma;
        2: DC_Chroma;
        3: AC_Chroma;
    endcase;
endfunction

interface JPEGFramewriter_ifc;
    method Action configure(Bit#(16) width, Bit#(16) height, SubsamplingMode_t mode);
    method Action start();
    method Bool done();

    //combinational table read clients, connected to TableStorage
    interface Client#(QuantTableIdx_t, UInt#(8)) quant_raw;
    interface Client#(HuffBitsIdx_t,   UInt#(8)) huff_bits;
    interface Client#(HuffValIdx_t,    UInt#(8)) huff_val;

    interface Put#(Maybe#(Bit#(8))) scan_data;
    interface Get#(Bit#(8)) byte_out;
endinterface

module mkJPEGFramewriter#(Bool en_chroma)(JPEGFramewriter_ifc);

    FIFO#(Maybe#(Bit#(8))) f_scan <- mkPipelineFIFO;
    FIFO#(Bit#(8))         f_out  <- mkPipelineFIFO;

    Reg#(State_t) rg_state <- mkReg(IDLE);

    //configuration
    Reg#(Bit#(16))          rg_width  <- mkRegU;
    Reg#(Bit#(16))          rg_height <- mkRegU;
    Reg#(SubsamplingMode_t) rg_mode   <- mkRegU;

    //byte counter within current state
    Reg#(UInt#(9)) rg_cnt <- mkReg(0);

    //DQT table selector: 0=luma, 1=chroma
    Reg#(Bit#(1)) rg_dqt <- mkReg(0);

    //DHT table selector: 0=DC_Luma, 1=AC_Luma, 2=DC_Chroma, 3=AC_Chroma
    Reg#(Bit#(2)) rg_dht <- mkReg(0);

    //pre-computed sum(BITS) for current DHT table
    Reg#(UInt#(9)) rg_huffval_total <- mkReg(0);

    //combinational table read wires (client side)
    Wire#(QuantTableIdx_t) w_qraw_req  <- mkWire;
    Wire#(UInt#(8))        w_qraw_resp <- mkWire;

    Wire#(HuffBitsIdx_t)   w_hbits_req  <- mkWire;
    Wire#(UInt#(8))        w_hbits_resp <- mkWire;

    Wire#(HuffValIdx_t)    w_hval_req  <- mkWire;
    Wire#(UInt#(8))        w_hval_resp <- mkWire;

    // ----------------------------------------------------------------
    // Constant header byte lookups
    // ----------------------------------------------------------------

    //SOI + APP0 (JFIF): 20 bytes
    function Bit#(8) jfif_hdr(UInt#(9) idx);
        return case (idx)
            0:  'hFF; 1:  'hD8;                        //SOI
            2:  'hFF; 3:  'hE0;                        //APP0
            4:  'h00; 5:  'h10;                        //Ls=16
            6:  'h4A; 7:  'h46;                        //"JF"
            8:  'h49; 9:  'h46;                        //"IF"
            10: 'h00;                                  //null terminator
            11: 'h01; 12: 'h02;                        //version 1.02
            13: 'h00;                                  //density units: none
            14: 'h00; 15: 'h48;                        //Xdensity = 72
            16: 'h00; 17: 'h48;                        //Ydensity = 72
            18: 'h00; 19: 'h00;                        //no thumbnail
            default: 0;
        endcase;
    endfunction

    //DQT marker header: FF DB 00 43 Pq_Tq  (5 bytes, Lq=67)
    function Bit#(8) dqt_head_byte(UInt#(9) idx, Bit#(1) tq);
        return case (idx)
            0: 'hFF; 1: 'hDB;      //DQT marker
            2: 'h00; 3: 'h43;      //Lq = 2 + 1 + 64 = 67 (16 bits)
            4: zeroExtend(tq);     //Pq=0 (8-bit precision), Tq
            default: 0;
        endcase;
    endfunction

    //SOF0: grayscale uses 1 component, color uses 3 components.
    function Bit#(8) sof0_byte(UInt#(9) idx);
        Bit#(8) sampfac = case (rg_mode)
            YCBCR_444: 'h11;
            YCBCR_422: 'h21;
            YCBCR_420: 'h22;
        endcase;
        if(!en_chroma) begin
            return case (idx)
                0:  'hFF; 1:  'hC0;                     //SOF0 marker
                2:  'h00; 3:  'h0B;                     //Lf = 8 + 3*Nf = 11
                4:  'h08;                               //P = 8 bits
                5:  rg_height[15:8]; 6: rg_height[7:0];
                7:  rg_width[15:8];  8: rg_width[7:0];
                9:  'h01;                               //Nf = 1
                10: 'h01; 11: 'h11;    12: 'h00;        //Y: 1x1, Tqi=0
                default: 0;
            endcase;
        end else begin
            return case (idx)
                0:  'hFF; 1:  'hC0;                     //SOF0 marker
                2:  'h00; 3:  'h11;                     //Lf = 8 + 3*Nf = 17
                4:  'h08;                               //P = 8 bits
                5:  rg_height[15:8]; 6: rg_height[7:0];
                7:  rg_width[15:8];  8: rg_width[7:0];
                9:  'h03;                               //Nf = 3
                10: 'h01; 11: sampfac; 12: 'h00;        //Y:  Hi/Vi per mode, Tqi=0
                13: 'h02; 14: 'h11;    15: 'h01;        //Cb: 1×1, Tqi=1
                16: 'h03; 17: 'h11;    18: 'h01;        //Cr: 1×1, Tqi=1
                default: 0;
            endcase;
        end
    endfunction

    //Tc|Th byte for DHT marker
    function Bit#(8) dht_tc_th(Bit#(2) tbl);
        return case (tbl)
            0: 'h00;   //DC table 0 (luma)
            1: 'h10;   //AC table 0 (luma)
            2: 'h01;   //DC table 1 (chroma)
            3: 'h11;   //AC table 1 (chroma)
        endcase;
    endfunction

    function Bit#(8) dht_head_byte(UInt#(9) idx, Bit#(2) table_id);
        //Lh = 2 + 1 + 16 + sum(BITS)
        Bit#(16) lh = 19 + zeroExtend(pack(rg_huffval_total));
        return case (idx)
            0: 'hFF;        1: 'hC4;        //DHT marker
            2: lh[15:8];    3: lh[7:0];     //Lh
            4: dht_tc_th(table_id);         //Tc|Th
            default: 0;
        endcase;
    endfunction

    //SOS: grayscale uses Ns=1, color uses Ns=3.
    function Bit#(8) sos_byte(UInt#(9) idx);
        if(!en_chroma) begin
            return case (idx)
                0: 'hFF; 1: 'hDA;                 //SOS marker
                2: 'h00; 3: 'h08;                 //Ls = 6 + 2*Ns = 8
                4: 'h01;                          //Ns = 1
                5: 'h01; 6: 'h00;                 //Y: Csj=1, Tdj=0, Taj=0
                7: 'h00;                          //Ss = 0
                8: 'h3F;                          //Se = 63
                9: 'h00;                          //Ah = 0, Al = 0
                default: 0;
            endcase;
        end else begin
            return case (idx)
                0:  'hFF; 1:  'hDA;                //SOS marker
                2:  'h00; 3:  'h0C;                //Ls = 6 + 2*Ns = 12
                4:  'h03;                          //Ns = 3
                5:  'h01; 6:  'h00;                //Y:  Csj=1, Tdj=0, Taj=0
                7:  'h02; 8:  'h11;                //Cb: Csj=2, Tdj=1, Taj=1
                9:  'h03; 10: 'h11;                //Cr: Csj=3, Tdj=1, Taj=1
                11: 'h00;                          //Ss = 0
                12: 'h3F;                          //Se = 63
                13: 'h00;                          //Ah = 0, Al = 0
                default: 0;
            endcase;
        end
    endfunction

    function Bool last_dht_table(Bit#(2) tbl);
        return en_chroma ? (tbl == 3) : (tbl == 1);
    endfunction


    // FSM 

    //emit SOI + APP0 (20 bytes)
    rule r_static_header (rg_state == STATIC_HEADER);
        f_out.enq(jfif_hdr(rg_cnt));
        if (rg_cnt == 19) begin
            rg_cnt   <= 0;
            rg_dqt   <= 0;
            rg_state <= DQT_HEAD;
        end else
            rg_cnt <= rg_cnt + 1;
    endrule

    //emit DQT marker header (5 bytes)
    rule r_dqt_head (rg_state == DQT_HEAD);
        f_out.enq(dqt_head_byte(rg_cnt, rg_dqt));
        if (rg_cnt == 4) begin
            rg_cnt   <= 0;
            rg_state <= DQT_DATA;
        end else
            rg_cnt <= rg_cnt + 1;
    endrule

    //JPEG spec (ITU-T T.81, B.2.4.1) requires DQT values in zigzag scan order
    let dqt_zigzag = zigzag_indices(False);

    //drive quant_raw address wire during DQT_DATA (zigzag-reordered)
    rule r_dqt_addr (rg_state == DQT_DATA);
        PixType_t pt = (rg_dqt == 0) ? Luma : Chroma;
        Bit#(6) scan_idx = truncate(pack(rg_cnt));
        w_qraw_req <= QuantTableIdx_t { pt: pt, idx: fromInteger(dqt_zigzag[scan_idx]) };
    endrule

    //emit 64 quantization table values
    rule r_dqt_data (rg_state == DQT_DATA);
        f_out.enq(pack(w_qraw_resp));
        if (rg_cnt == 63) begin
            rg_cnt <= 0;
            if (en_chroma && rg_dqt == 0) begin
                rg_dqt   <= 1;
                rg_state <= DQT_HEAD;
            end else
                rg_state <= DHT_SUM;
        end else
            rg_cnt <= rg_cnt + 1;
    endrule

    //drive huff_bits address wire during DHT_SUM and DHT_BITS
    rule r_hbits_addr (rg_state == DHT_SUM || rg_state == DHT_BITS);
        w_hbits_req <= HuffBitsIdx_t { htt: dht_htt(rg_dht), idx: truncate(pack(rg_cnt)) };
    endrule

    //pre-compute sum(BITS[0..15]) for current DHT table
    //17 cycles: cycles 0..15 accumulate, cycle 16 transitions (register holds final sum)
    rule r_dht_sum (rg_state == DHT_SUM);
        if (rg_cnt <= 15) begin
            rg_huffval_total <= rg_huffval_total + extend(w_hbits_resp);
            rg_cnt <= rg_cnt + 1;
        end else begin
            rg_cnt   <= 0;
            rg_state <= DHT_HEAD;
        end
    endrule

    //emit DHT marker: FF C4 Lh_hi Lh_lo Tc_Th  (5 bytes)
    rule r_dht_head (rg_state == DHT_HEAD);
        Bit#(8) b = dht_head_byte(rg_cnt, rg_dht);
        f_out.enq(b);
        if (rg_cnt == 4) begin
            rg_cnt   <= 0;
            rg_state <= DHT_BITS;
        end else
            rg_cnt <= rg_cnt + 1;
    endrule

    //emit 16 BITS bytes
    rule r_dht_bits (rg_state == DHT_BITS);
        f_out.enq(pack(w_hbits_resp));
        if (rg_cnt == 15) begin
            rg_cnt <= 0;
            if (rg_huffval_total == 0) begin
                //no HUFFVAL entries - advance to next table or to SOF0
                if (last_dht_table(rg_dht)) begin
                    rg_huffval_total <= 0;
                    rg_state         <= SOF0;
                end
                else begin
                    rg_dht   <= rg_dht + 1;
                    rg_state <= DHT_SUM;
                end
            end else
                rg_state <= DHT_VAL;
        end else
            rg_cnt <= rg_cnt + 1;
    endrule

    //drive huff_val address wire during DHT_VAL
    rule r_hval_addr (rg_state == DHT_VAL);
        w_hval_req <= HuffValIdx_t { htt: dht_htt(rg_dht), idx: truncate(pack(rg_cnt)) };
    endrule

    //emit HUFFVAL bytes
    rule r_dht_val (rg_state == DHT_VAL);
        f_out.enq(pack(w_hval_resp));
        if (rg_cnt == rg_huffval_total - 1) begin
            rg_cnt           <= 0;
            rg_huffval_total <= 0;
            if (last_dht_table(rg_dht))
                rg_state <= SOF0;
            else begin
                rg_dht   <= rg_dht + 1;
                rg_state <= DHT_SUM;
            end
        end else
            rg_cnt <= rg_cnt + 1;
    endrule

    //emit SOF0 frame header (19 bytes)
    rule r_sof0 (rg_state == SOF0);
        f_out.enq(sof0_byte(rg_cnt));
        if (rg_cnt == (en_chroma ? 18 : 12)) begin
            rg_cnt           <= 0;
            rg_dht           <= 0;
            rg_huffval_total <= 0;
            rg_state         <= SCAN_HEAD;
        end else
            rg_cnt <= rg_cnt + 1;
    endrule

    //emit SOS header (14 bytes)
    rule r_scan_header (rg_state == SCAN_HEAD);
        f_out.enq(sos_byte(rg_cnt));
        if (rg_cnt == (en_chroma ? 13 : 9)) begin
            rg_cnt   <= 0;
            rg_state <= SCAN;
        end else
            rg_cnt <= rg_cnt + 1;
    endrule

    //passthrough scan data; tagged Invalid signals end of scan
    rule r_scan (rg_state == SCAN);
        let mb = f_scan.first; f_scan.deq;
        case (mb) matches
            tagged Valid .b: f_out.enq(b);
            tagged Invalid: begin
                rg_state <= EOI;
                rg_cnt   <= 0;
            end
        endcase
    endrule

    //emit EOI marker (FF D9)
    rule r_eoi (rg_state == EOI);
        f_out.enq((rg_cnt == 0) ? 'hFF : 'hD9);
        if (rg_cnt == 1) begin
            rg_state <= DONE;
            rg_cnt   <= 0;
        end else
            rg_cnt <= rg_cnt + 1;
    endrule


    method Action configure(Bit#(16) width, Bit#(16) height, SubsamplingMode_t mode);
        rg_width  <= width;
        rg_height <= height;
        rg_mode   <= mode;
    endmethod

    method Action start() if (rg_state == IDLE || rg_state == DONE);
        rg_state <= STATIC_HEADER;
        rg_cnt   <= 0;
    endmethod

    method Bool done() = (rg_state == DONE);

    interface quant_raw = toGPClient(asReg(w_qraw_req), asReg(w_qraw_resp));
    interface huff_bits = toGPClient(asReg(w_hbits_req), asReg(w_hbits_resp));
    interface huff_val  = toGPClient(asReg(w_hval_req), asReg(w_hval_resp));

    interface scan_data = toPut(f_scan);
    interface byte_out  = toGet(f_out);

endmodule

endpackage