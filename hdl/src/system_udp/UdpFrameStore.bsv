package UdpFrameStore;

import BRAMFIFO :: *;
import DefaultValue :: *;
import FIFO :: *;
import FIFOF :: *;
import GetPut :: *;
import RWire :: *;
import AXI4_Master :: *;
import AXI4_Stream :: *;
import AXI4_Types :: *;

typedef enum { STORE_IDLE, STORE_READ, STORE_VERIFY, STORE_PEEK, STORE_WRITE } UdpStoreMode_t deriving(Bits, Eq, FShow);

typedef struct {
    UdpStoreMode_t mode;
    UInt#(32)      address;
    UInt#(32)      count;
    Bit#(32)       data;
    Bit#(4)        strb;
    Bool           reply;
} UdpStoreCommand_t deriving(Bits, Eq, FShow);

function Bool udp_frame_range_valid(UInt#(32) base, UInt#(32) count);
    UInt#(33) limit = extend(base) + extend(count);
    return count != 0 && limit <= 'h10000000;
endfunction

interface UdpFrameStore_ifc;
    interface AXI4_Master_Rd_Fab#(30, 32, 4, 0)  m_rd;
    interface AXI4_Master_Wr_Fab#(30, 32, 4, 0)  m_wr;
    interface Get#(AXI4_Stream_Pkg#(24, 0))      pixels;
    interface Put#(Tuple2#(UInt#(32), Bit#(24))) load;
    interface Get#(Tuple2#(Bit#(32), Bool))      memory_response;
    method Action                                start(UInt#(32) base, UInt#(32) count, Bool verify);
    method Action                                memory(UInt#(32) address, Bool write, Bit#(32) data, Bit#(4) strb);
    method Bool                                  idle;
    method Bool                                  reader_active;
    method Bool                                  loading;
    method Bool                                  verify_done;
    method Bit#(32)                              checksum1;
    method Bit#(32)                              checksum2;
    method Bool                                  error;
endinterface

/*
 * One memory owner at a time. Read bursts stop at 4 KiB boundaries and have at most
 * two outstanding addresses. The BRAM queue backpressures AXI responses independently
 * of the encoder. Loader writes and peek/poke finish only after the AXI response.
 */
module mkUdpFrameStore(UdpFrameStore_ifc);
    AXI4_Master_Rd#(30, 32, 4, 0)        i_rd          <- mkAXI4_Master_Rd(2, 2, False);
    AXI4_Master_Wr#(30, 32, 4, 0)        i_wr          <- mkAXI4_Master_Wr(2, 2, 2, False);
    FIFOF#(UdpStoreCommand_t)            f_commands    <- mkFIFOF;
    FIFOF#(Tuple2#(UInt#(32), Bit#(24))) f_load        <- mkFIFOF;
    FIFO#(Bool)                          f_outstanding <- mkSizedFIFO(2);
    FIFOF#(AXI4_Stream_Pkg#(24, 0))      f_pixels      <- mkSizedBRAMFIFOF(512);
    FIFOF#(Tuple2#(Bit#(32), Bool))      f_memory      <- mkFIFOF;

    Reg#(UdpStoreMode_t) rg_mode          <- mkReg(STORE_IDLE);
    Reg#(UInt#(32))      rg_address       <- mkReg(0);
    Reg#(UInt#(32))      rg_request_left  <- mkReg(0);
    Reg#(UInt#(32))      rg_response_left <- mkReg(0);
    Reg#(Bit#(32))       rg_data          <- mkReg(0);
    Reg#(Bit#(4))        rg_strb          <- mkReg(0);
    Reg#(Bool)           rg_reply         <- mkReg(False);
    Reg#(Bool)           rg_written       <- mkReg(False);
    Reg#(Bit#(32))       rg_sum1          <- mkReg(0);
    Reg#(Bit#(32))       rg_sum2          <- mkReg(0);
    Reg#(Bool)           rg_verified      <- mkReg(False);
    Reg#(Bool)           rg_error         <- mkReg(False);

    RWire#(UdpStoreCommand_t)       w_begin         <- mkRWire;
    RWire#(UInt#(32))               w_issued        <- mkRWire;
    RWire#(AXI4_Read_Rs#(32, 4, 0)) w_received      <- mkRWire;
    PulseWire                       pw_read_finish  <- mkPulseWire;
    PulseWire                       pw_write_finish <- mkPulseWire;
    PulseWire                       pw_pixel_finish <- mkPulseWire;
    PulseWire                       pw_written      <- mkPulseWire;
    PulseWire                       pw_error        <- mkPulseWire;

    rule r_accept (rg_mode == STORE_IDLE && (f_commands.notEmpty || f_load.notEmpty));
        if(f_commands.notEmpty) begin
            w_begin.wset(f_commands.first);
            f_commands.deq;
        end else begin
            let pixel = f_load.first;
            f_load.deq;
            w_begin.wset(UdpStoreCommand_t { mode: STORE_WRITE, address: tpl_1(pixel), count: 0, data: zeroExtend(tpl_2(pixel)), strb: '1, reply: False });
        end
    endrule

    rule r_issue ((rg_mode == STORE_READ || rg_mode == STORE_VERIFY || rg_mode == STORE_PEEK) && rg_request_left != 0);
        UInt#(32)               boundary = 1024 - zeroExtend(unpack(pack(rg_address)[9:0]));
        UInt#(32)               count    = min(256, min(boundary, rg_request_left));
        AXI4_Read_Rq#(30, 4, 0) request  = defaultValue;
        request.addr         = truncate(pack(rg_address << 2));
        request.burst_size   = B4;
        request.burst_type   = INCR;
        request.burst_length = truncate(count - 1);
        i_rd.request.put(request);
        f_outstanding.enq(True);
        w_issued.wset(count);
    endrule

    rule r_receive (rg_mode == STORE_READ || rg_mode == STORE_VERIFY || rg_mode == STORE_PEEK);
        let  response <- i_rd.response.get;
        Bool last     = rg_response_left == 1;
        if(rg_mode == STORE_READ) f_pixels.enq(AXI4_Stream_Pkg { data: truncate(response.data), keep: '1, user: 0, dest: 0, id: 0, last: last });
        if(rg_mode == STORE_PEEK) f_memory.enq(tuple2(response.data, response.resp != OKAY));
        if(last && rg_mode != STORE_READ) pw_read_finish.send;
        if(response.last) f_outstanding.deq;
        w_received.wset(response);
    endrule

    rule r_write (rg_mode == STORE_WRITE && !rg_written);
        AXI4_Write_Rq_Addr#(30, 4, 0) request = defaultValue;
        request.addr       = truncate(pack(rg_address << 2));
        request.burst_size = B4;
        request.burst_type = INCR;
        i_wr.request_addr.put(request);
        i_wr.request_data.put(AXI4_Write_Rq_Data { data: rg_data, strb: rg_strb, last: True, user: 0 });
        pw_written.send;
    endrule

    rule r_write_response (rg_mode == STORE_WRITE && rg_written);
        let response <- i_wr.response.get;
        if(rg_reply) f_memory.enq(tuple2(0, response.resp != OKAY));
        if(response.resp != OKAY) pw_error.send;
        pw_write_finish.send;
    endrule

    //all persistent engine state is owned here
    (* fire_when_enabled, no_implicit_conditions *)
    rule r_state;
        Bool failed = pw_error;
        if(w_begin.wget matches tagged Valid .command) begin
            rg_mode          <= command.mode;
            rg_address       <= command.address;
            rg_request_left  <= command.count;
            rg_response_left <= command.count;
            rg_data          <= command.data;
            rg_strb          <= command.strb;
            rg_reply         <= command.reply;
            rg_written       <= False;
            if(command.mode == STORE_VERIFY) begin
                rg_sum1     <= 0;
                rg_sum2     <= 0;
                rg_verified <= False;
            end
        end else begin
            if(w_issued.wget matches tagged Valid .count) begin
                rg_address      <= rg_address + count;
                rg_request_left <= rg_request_left - count;
            end
            if(w_received.wget matches tagged Valid .response) begin
                rg_response_left <= rg_response_left - 1;
                if(response.resp != OKAY) failed = True;
                if(rg_mode == STORE_VERIFY) begin
                    let sum = rg_sum1 + response.data;
                    rg_sum1 <= sum;
                    rg_sum2 <= rg_sum2 + sum;
                end
            end
            if(pw_written) rg_written <= True;
            if(pw_read_finish || pw_write_finish || pw_pixel_finish) begin
                rg_mode <= STORE_IDLE;
                if(rg_mode == STORE_VERIFY) rg_verified <= True;
            end
        end
        if(failed) rg_error <= True;
    endrule

    interface m_rd            = i_rd.fab;
    interface m_wr            = i_wr.fab;
    interface load            = toPut(f_load);
    interface memory_response = toGet(f_memory);

    interface Get pixels;
        method ActionValue#(AXI4_Stream_Pkg#(24, 0)) get;
            let pixel = f_pixels.first;
            f_pixels.deq;
            if(pixel.last) pw_pixel_finish.send;
            return pixel;
        endmethod
    endinterface

    method Action start(UInt#(32) base, UInt#(32) count, Bool verify) if(rg_mode == STORE_IDLE && !f_commands.notEmpty && !f_pixels.notEmpty);
        f_commands.enq(UdpStoreCommand_t { mode: verify ? STORE_VERIFY : STORE_READ, address: base, count: count, data: 0, strb: 0, reply: False });
    endmethod

    method Action memory(UInt#(32) address, Bool write, Bit#(32) data, Bit#(4) strb) if(rg_mode == STORE_IDLE && !f_commands.notEmpty);
        f_commands.enq(UdpStoreCommand_t { mode: write ? STORE_WRITE : STORE_PEEK, address: address, count: 1, data: data, strb: strb, reply: True });
    endmethod

    method idle          = rg_mode == STORE_IDLE && !f_commands.notEmpty && !f_load.notEmpty && !f_pixels.notEmpty;
    method reader_active = rg_mode == STORE_READ;
    method loading       = (rg_mode == STORE_WRITE && !rg_reply) || f_load.notEmpty;
    method verify_done   = rg_verified;
    method checksum1     = rg_sum1;
    method checksum2     = rg_sum2;
    method error         = rg_error;
endmodule

endpackage
