package UdpPacketizer;

import BRAMFIFO :: *;
import FIFOF :: *;
import GetPut :: *;
import RWire :: *;

import AXI4_Stream :: *;
import EthernetTypes :: *;
import UdpRgmiiCsr :: *;

typedef enum { UdpCollect, UdpRequest, UdpHeader, UdpPayload } UdpPacketState_t deriving(Bits, Eq, FShow);

interface UdpPacketizer_ifc;
    interface Put#(AXI4_Stream_Pkg#(8, 0)) jpeg;
    interface Get#(UdpTxRequest)           tx_header;
    interface EthernetStreamSource_ifc     tx_payload;
    method Bool                            frame_done;
    method Bool                            packet_sent;
endinterface

module mkUdpPacketizer(UdpPacketizer_ifc);
    FIFOF#(Bit#(8))                f_bytes         <- mkSizedBRAMFIFOF(1024);
    AXI4_Stream_Wr#(8, 1)          i_out           <- mkAXI4_Stream_Wr(2);
    Reg#(UdpPacketState_t)         rg_state        <- mkReg(UdpCollect);
    Reg#(UInt#(11))                rg_length       <- mkReg(0);
    Reg#(UInt#(11))                rg_sent         <- mkReg(0);
    Reg#(UInt#(4))                 rg_header_index <- mkReg(0);
    Reg#(Bit#(16))                 rg_frame        <- mkReg(0);
    Reg#(Bit#(16))                 rg_sequence     <- mkReg(0);
    Reg#(Bool)                     rg_last         <- mkReg(False);
    Reg#(Bool)                     rg_wait_final   <- mkReg(False);
    RWire#(AXI4_Stream_Pkg#(8, 0)) w_byte          <- mkRWire;
    PulseWire                      pw_request      <- mkPulseWire;
    PulseWire                      pw_header       <- mkPulseWire;
    PulseWire                      pw_payload      <- mkPulseWire;
    PulseWire                      pw_packet       <- mkPulseWire;
    PulseWire                      pw_done         <- mkPulseWire;

    rule r_header (rg_state == UdpHeader);
        Bit#(16) length = zeroExtend(pack(rg_length));
        Bit#(8)  data   = case(rg_header_index)
            0: 'h4a;
            1: zeroExtend(pack(rg_last));
            2: rg_frame[15:8];
            3: rg_frame[7:0];
            4: rg_sequence[15:8];
            5: rg_sequence[7:0];
            6: length[15:8];
            default: length[7:0];
        endcase;
        i_out.pkg.put(AXI4_Stream_Pkg {
            data: data,
            keep: 1,
            user: 0,
            dest: 0,
            id  : 0,
            last: False
        });
        pw_header.send;
    endrule

    rule r_payload (rg_state == UdpPayload && !rg_wait_final);
        i_out.pkg.put(AXI4_Stream_Pkg {
            data: f_bytes.first,
            keep: 1,
            user: 0,
            dest: 0,
            id  : 0,
            last: rg_sent + 1 == rg_length
        });
        f_bytes.deq;
        pw_payload.send;
    endrule

    Wire#(Bool) w_ready <- mkDWire(False);
    //finish at the UDP boundary handshake, rather than at the local output queue
    rule r_complete (rg_wait_final && w_ready && i_out.fab.tvalid && i_out.fab.tlast);
        pw_packet.send;
        if(rg_last) pw_done.send;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_state;
        if(w_byte.wget matches tagged Valid .byte_in) begin
            rg_length <= rg_length + 1;
            if(byte_in.last || rg_length == 1023) begin
                rg_last  <= byte_in.last;
                rg_state <= UdpRequest;
            end
        end else if(pw_request) begin
            rg_state        <= UdpHeader;
            rg_header_index <= 0;
            rg_sent         <= 0;
        end else if(pw_header) begin
            rg_header_index <= rg_header_index + 1;
            if(rg_header_index == 7) rg_state <= UdpPayload;
        end else if(pw_payload) begin
            rg_sent <= rg_sent + 1;
            if(rg_sent + 1 == rg_length) rg_wait_final <= True;
        end else if(pw_packet) begin
            rg_wait_final <= False;
            rg_state      <= UdpCollect;
            rg_length     <= 0;
            rg_sequence   <= rg_last ? 0 : rg_sequence + 1;
            if(rg_last) rg_frame <= rg_frame + 1;
        end
    endrule

    interface Put jpeg;
        method Action put(AXI4_Stream_Pkg#(8, 0) byte_in) if(rg_state == UdpCollect);
            f_bytes.enq(byte_in.data);
            w_byte.wset(byte_in);
        endmethod
    endinterface
    interface Get tx_header;
        method ActionValue#(UdpTxRequest) get if(rg_state == UdpRequest);
            pw_request.send;
            return UdpTxRequest {
                payload_length: zeroExtend(pack(rg_length)) + 8,
                checksum      : 0
            };
        endmethod
    endinterface
    interface EthernetStreamSource_ifc tx_payload;
        method Action ptready(Bool ready);
            w_ready <= ready;
            i_out.fab.ptready(ready);
        endmethod
        method tvalid = i_out.fab.tvalid;
        method tdata  = i_out.fab.tdata;
        method tlast  = i_out.fab.tlast;
        method tuser  = i_out.fab.tuser;
        method tkeep  = i_out.fab.tkeep;
        method tDest  = i_out.fab.tDest;
        method tid    = i_out.fab.tid;
    endinterface
    method frame_done  = pw_done;
    method packet_sent = pw_packet;
endmodule

endpackage
