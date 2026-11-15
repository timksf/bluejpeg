package TbUdpPacketizer;

import Connectable :: *;
import GetPut :: *;
import StmtFSM :: *;

import AXI4_Stream :: *;
import TestHelper :: *;
import UdpModel :: *;
import UdpPacketizer :: *;
import UdpRgmiiCsr :: *;

function UInt#(32) frame_length(UInt#(16) frame);
    return case(frame)
        0: 1;
        1: 1023;
        2: 1024;
        3: 1025;
        4: 2048;
        default: 3073;
    endcase;
endfunction

function Bit#(8) payload_byte(UInt#(16) frame, UInt#(32) index);
    return truncate(pack(index ^ (index >> 8) ^ (zeroExtend(frame) * 37)));
endfunction

module [Module] mkTbUdpPacketizer(TestHandler_ifc);
    let i_dut <- mkUdpPacketizer;
    let i_udp <- mkUdpModel;
    mkConnection(i_dut.tx_header, i_udp.tx_header);
    mkConnection(i_dut.tx_payload, i_udp.tx_payload);

    rule r_unused_rx;
        i_udp.rx_payload.ptready(True);
    endrule

    Reg#(Bool)      rg_active        <- mkReg(False);
    Reg#(UInt#(32)) rg_cycle         <- mkReg(0);
    Reg#(UInt#(16)) rg_send_frame    <- mkReg(0);
    Reg#(UInt#(32)) rg_send_byte     <- mkReg(0);
    Reg#(UInt#(16)) rg_receive_frame <- mkReg(0);
    Reg#(UInt#(32)) rg_receive_byte  <- mkReg(0);
    Reg#(UInt#(16)) rg_sequence      <- mkReg(0);
    Reg#(UInt#(32)) rg_packet_byte   <- mkReg(0);
    Reg#(UInt#(32)) rg_length        <- mkReg(0);
    Reg#(Bit#(64))  rg_header        <- mkReg(0);
    Reg#(UInt#(16)) rg_done_frames   <- mkReg(0);
    Reg#(UInt#(16)) rg_done_packets  <- mkReg(0);
    Reg#(Bool)      rg_overlap       <- mkReg(False);
    Reg#(Bool)      rg_sending       <- mkReg(False);

    function Action check(Bool condition, Fmt message);
        action
            if(!condition) begin
                $display("ERROR: ", message);
                $finish(1);
            end
        endaction
    endfunction

    rule r_tick (rg_active);
        rg_cycle <= rg_cycle + 1;
        check(rg_cycle < 100000, $format("packetizer timeout"));
    endrule

    rule r_send (rg_active && rg_send_frame < 6);
        Bool last = rg_send_byte + 1 == frame_length(rg_send_frame);
        i_dut.jpeg.put(AXI4_Stream_Pkg {
            data: payload_byte(rg_send_frame, rg_send_byte),
            keep: 1,
            user: 0,
            dest: 0,
            id  : 0,
            last: last
        });
        if(rg_sending) rg_overlap <= True;
        rg_send_byte <= last ? 0 : rg_send_byte + 1;
        if(last) rg_send_frame <= rg_send_frame + 1;
    endrule

    rule r_monitor;
        if(i_dut.frame_done) rg_done_frames <= rg_done_frames + 1;
        if(i_dut.packet_sent) rg_done_packets <= rg_done_packets + 1;
    endrule

    Stmt main = seq
        i_udp.hold_tx(True);
        rg_active <= True;
        //fill the queues before allowing any payload to leave
        delay(5000);
        check(rg_done_frames == 0 && rg_done_packets == 0, $format("completion before final handshake"));
        i_udp.hold_tx(False);
        while(rg_receive_frame < 6) seq
            rg_receive_byte <= 0;
            rg_sequence <= 0;
            while(rg_receive_byte < frame_length(rg_receive_frame)) seq
                action
                    let header <- i_udp.receive_header.get;
                    let length = min(1024, frame_length(rg_receive_frame) - rg_receive_byte);
                    check(header.payload_length == truncate(pack(length + 8)) && header.checksum == 0, $format("UDP length or checksum"));
                    rg_length <= length;
                    rg_header <= 0;
                    rg_sending <= True;
                endaction
                for(rg_packet_byte <= 0; rg_packet_byte < 8; rg_packet_byte <= rg_packet_byte + 1) action
                    let byte_in <- i_udp.receive_byte.get;
                    check(!byte_in.last && byte_in.keep == 1 && byte_in.user == 0, $format("header sidebands"));
                    rg_header <= (rg_header << 8) | zeroExtend(byte_in.data);
                endaction
                action
                    Bool last = rg_receive_byte + rg_length == frame_length(rg_receive_frame);
                    Bit#(64) expected = {Bit#(8)'('h4a), Bit#(8)'(zeroExtend(pack(last))), pack(rg_receive_frame), pack(rg_sequence), Bit#(16)'(truncate(pack(rg_length)))};
                    check(rg_header == expected, $format("packet header got %016x expected %016x", rg_header, expected));
                endaction
                for(rg_packet_byte <= 0; rg_packet_byte < rg_length; rg_packet_byte <= rg_packet_byte + 1) seq
                    //stall beyond the periodic ready throttling, including the final byte
                    if(rg_packet_byte == rg_length - 1) seq
                        i_udp.hold_tx(True);
                        delay(23);
                        i_udp.hold_tx(False);
                    endseq
                    action
                        let byte_in <- i_udp.receive_byte.get;
                        check(byte_in.data == payload_byte(rg_receive_frame, rg_receive_byte), $format("payload mismatch frame %0d byte %0d", rg_receive_frame, rg_receive_byte));
                        check(byte_in.last == (rg_packet_byte + 1 == rg_length) && byte_in.keep == 1 && byte_in.user == 0 && byte_in.dest == 0 && byte_in.id == 0, $format("payload sidebands"));
                        rg_receive_byte <= rg_receive_byte + 1;
                    endaction
                endseq
                rg_sending <= False;
                rg_sequence <= rg_sequence + 1;
            endseq
            rg_receive_frame <= rg_receive_frame + 1;
        endseq
        delay(16);
        check(rg_send_frame == 6 && rg_done_frames == 6 && rg_done_packets == 11 && rg_overlap, $format("completion counts or overlap, frames %0d packets %0d overlap %0d", rg_done_frames, rg_done_packets, rg_overlap));
        rg_active <= False;
        $display("TbUdpPacketizer PASSED (six frames, 11 packets, overlapping collection, stalled output)");
    endseq;
    FSM i_fsm <- mkFSM(main);
    method go   = i_fsm.start;
    method done = i_fsm.done;
endmodule

endpackage
