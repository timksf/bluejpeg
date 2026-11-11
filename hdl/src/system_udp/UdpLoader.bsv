package UdpLoader;

import BRAMFIFO :: *;
import FIFOF :: *;
import GetPut :: *;

import AXI4_Stream :: *;
import EthernetTypes :: *;

typedef enum { UdpLoadIdle, UdpLoadReceive, UdpLoadValidate, UdpLoadCommit, UdpLoadDiscard } UdpLoadState_t deriving(Bits, Eq, FShow);

interface UdpLoader_ifc;
    interface Put#(UdpRxHeader)                  rx_header;
    interface EthernetStreamSink_ifc             rx_payload;
    interface Get#(Tuple2#(UInt#(32), Bit#(24))) pixels;
    method Action                                configure(Bool enabled, UInt#(32) base, UInt#(32) count);
    method Bool                                  active;
    method Bit#(32)                              packets;
    method Bit#(32)                              pixels_written;
    method Bit#(32)                              dropped;
endinterface

/*
 * Validate the whole datagram before issuing writes, including actual length, tuser,
 * pixel bounds and the final byte. A rejected packet is drained without touching RAM.
 * This keeps duplicate loads idempotent and malformed loads atomic.
 */
module mkUdpLoader(UdpLoader_ifc);
    FIFOF#(UdpRxHeader)                  f_headers <- mkFIFOF;
    AXI4_Stream_Rd#(8, 1)                i_in      <- mkAXI4_Stream_Rd(2);
    FIFOF#(Bit#(24))                     f_packet  <- mkSizedBRAMFIFOF(512);
    FIFOF#(Tuple2#(UInt#(32), Bit#(24))) f_pixels  <- mkFIFOF;
    Wire#(Bool)                          w_enabled <- mkDWire(False);
    Wire#(UInt#(32))                     w_base    <- mkDWire(0);
    Wire#(UInt#(32))                     w_count   <- mkDWire(0);

    Reg#(UdpLoadState_t) rg_state       <- mkReg(UdpLoadIdle);
    Reg#(Bool)           rg_bad         <- mkReg(False);
    Reg#(UInt#(16))      rg_length      <- mkReg(0);
    Reg#(UInt#(17))      rg_received    <- mkReg(0);
    Reg#(UInt#(10))      rg_pixel_count <- mkReg(0);
    Reg#(UInt#(10))      rg_committed   <- mkReg(0);
    Reg#(UInt#(2))       rg_component   <- mkReg(0);
    Reg#(Bit#(24))       rg_pixel       <- mkReg(0);
    Reg#(Bit#(32))       rg_index       <- mkReg(0);
    Reg#(UInt#(32))      rg_base        <- mkReg(0);
    Reg#(UInt#(32))      rg_limit       <- mkReg(0);
    Reg#(UInt#(32))      rg_available   <- mkReg(0);
    Reg#(Bit#(32))       rg_packets     <- mkReg(0);
    Reg#(Bit#(32))       rg_pixels      <- mkReg(0);
    Reg#(Bit#(32))       rg_dropped     <- mkReg(0);

    rule r_loader;
        case(rg_state)
            UdpLoadIdle: begin
                let header = f_headers.first;
                f_headers.deq;
                UInt#(16) length = unpack(header.length) - 8;
                rg_bad         <= !w_enabled || header.dest_port != 5000 || header.length < 15 || header.length > 1452;
                rg_length      <= length;
                rg_received    <= 0;
                rg_pixel_count <= 0;
                rg_component   <= 0;
                rg_pixel       <= 0;
                rg_index       <= 0;
                rg_base        <= w_base;
                rg_limit       <= w_count;
                rg_committed   <= 0;
                if(header.length <= 8) rg_dropped <= rg_dropped + 1;
                else rg_state <= UdpLoadReceive;
            end
            UdpLoadReceive: begin
                let  byte_in <- i_in.pkg.get;
                Bool bad     = rg_bad || byte_in.user != 0 || byte_in.keep != 1 || rg_received >= zeroExtend(rg_length);
                rg_received <= min(rg_received + 1, 65536);
                if(rg_received < 4) begin
                    Bit#(32) index = (rg_index << 8) | zeroExtend(byte_in.data);
                    rg_index <= index;
                    if(rg_received == 3) begin
                        rg_available <= rg_limit - unpack(index);
                        if(unpack(index) >= rg_limit) bad = True;
                    end
                end else if(!bad) begin
                    Bit#(24) pixel = (rg_pixel << 8) | zeroExtend(byte_in.data);
                    rg_pixel     <= pixel;
                    rg_component <= rg_component == 2 ? 0 : rg_component + 1;
                    if(rg_component == 2) begin
                        f_packet.enq(pixel);
                        rg_pixel_count <= rg_pixel_count + 1;
                    end
                end
                rg_bad <= bad;
                if(byte_in.last) rg_state <= UdpLoadValidate;
            end
            UdpLoadValidate: begin
                if(rg_bad || rg_received != zeroExtend(rg_length) || rg_component != 0 || rg_pixel_count == 0 || zeroExtend(rg_pixel_count) > rg_available) begin
                    rg_dropped <= rg_dropped + 1;
                    rg_state   <= UdpLoadDiscard;
                end else begin
                    rg_packets <= rg_packets + 1;
                    rg_state   <= UdpLoadCommit;
                end
            end
            UdpLoadCommit: begin
                f_pixels.enq(tuple2(rg_base + unpack(rg_index) + zeroExtend(rg_committed), f_packet.first));
                f_packet.deq;
                rg_pixels    <= rg_pixels + 1;
                rg_committed <= rg_committed + 1;
                if(rg_committed + 1 == rg_pixel_count) rg_state <= UdpLoadIdle;
            end
            UdpLoadDiscard: begin
                if(f_packet.notEmpty) f_packet.deq;
                else rg_state <= UdpLoadIdle;
            end
        endcase
    endrule

    interface rx_header  = toPut(f_headers);
    interface rx_payload = i_in.fab;
    interface pixels     = toGet(f_pixels);
    method Action configure(Bool enabled, UInt#(32) base, UInt#(32) count);
        w_enabled <= enabled;
        w_base    <= base;
        w_count   <= count;
    endmethod
    method active         = rg_state != UdpLoadIdle || f_headers.notEmpty || f_pixels.notEmpty;
    method packets        = rg_packets;
    method pixels_written = rg_pixels;
    method dropped        = rg_dropped;
endmodule

endpackage
