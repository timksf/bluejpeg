package UdpPatternRam;

import BRAM :: *;
import DefaultValue :: *;
import FIFO :: *;
import GetPut :: *;
import RWire :: *;
import AXI4_Slave :: *;
import AXI4_Types :: *;

interface UdpPatternRam_ifc;
    interface AXI4_Slave_Rd_Fab#(30, 32, 4, 0) s_rd;
    interface AXI4_Slave_Wr_Fab#(30, 32, 4, 0) s_wr;
endinterface

//temporary board frame store, the 24-bit ROM file zero extends to the required word format
module mkUdpPatternRam(UdpPatternRam_ifc);
    BRAM_Configure cfg = defaultValue;
    cfg.memorySize   = 36864;
    cfg.outFIFODepth = 4;
    cfg.loadFormat   = tagged Hex "pattern_192x192.mem";

    BRAM2PortBE#(Bit#(16), Bit#(32), 4) i_ram            <- mkBRAM2ServerBE(cfg);
    AXI4_Slave_Rd#(30, 32, 4, 0)        i_rd             <- mkAXI4_Slave_Rd(2, 2);
    AXI4_Slave_Wr#(30, 32, 4, 0)        i_wr             <- mkAXI4_Slave_Wr(2, 2, 2);
    FIFO#(Tuple3#(Bit#(4), Bool, Bool)) f_reads          <- mkSizedFIFO(4);
    Reg#(UInt#(9))                      rg_read_left     <- mkReg(0);
    Reg#(Bit#(30))                      rg_read_address  <- mkReg(0);
    Reg#(Bit#(4))                       rg_read_id       <- mkReg(0);
    Reg#(Bool)                          rg_read_error    <- mkReg(False);
    Reg#(UInt#(9))                      rg_write_left    <- mkReg(0);
    Reg#(Bit#(30))                      rg_write_address <- mkReg(0);
    Reg#(Bit#(4))                       rg_write_id      <- mkReg(0);
    Reg#(Bool)                          rg_write_error   <- mkReg(False);

    RWire#(AXI4_Read_Rq#(30, 4, 0))       w_read   <- mkRWire;
    RWire#(AXI4_Write_Rq_Addr#(30, 4, 0)) w_write  <- mkRWire;
    PulseWire                             pw_read  <- mkPulseWire;
    PulseWire                             pw_write <- mkPulseWire;

    rule r_read_address (rg_read_left == 0);
        let request <- i_rd.request.get;
        w_read.wset(request);
    endrule

    rule r_read (rg_read_left != 0);
        Bool error = rg_read_error || rg_read_address >= 147456;
        i_ram.portA.request.put(BRAMRequestBE { writeen: 0, responseOnWrite: False, address: error ? 0 : truncate(rg_read_address >> 2), datain: 0 });
        f_reads.enq(tuple3(rg_read_id, rg_read_left == 1, error));
        pw_read.send;
    endrule

    rule r_read_response;
        let data <- i_ram.portA.response.get;
        match {.id, .last, .error} = f_reads.first;
        f_reads.deq;
        i_rd.response.put(AXI4_Read_Rs { data: error ? 0 : data, id: id, last: last, resp: error ? DECERR : OKAY, user: 0 });
    endrule

    rule r_write_address (rg_write_left == 0);
        let request <- i_wr.request_addr.get;
        w_write.wset(request);
    endrule

    rule r_write (rg_write_left != 0);
        let  data  <- i_wr.request_data.get;
        Bool error = rg_write_error || rg_write_address >= 147456;
        if(!error) i_ram.portB.request.put(BRAMRequestBE { writeen: data.strb, responseOnWrite: False, address: truncate(rg_write_address >> 2), datain: data.data });
        if(rg_write_left == 1) i_wr.response.put(AXI4_Write_Rs { id: rg_write_id, resp: error ? DECERR : OKAY, user: 0 });
        pw_write.send;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_state;
        if(w_read.wget matches tagged Valid .request) begin
            rg_read_left    <= zeroExtend(request.burst_length) + 1;
            rg_read_address <= request.addr;
            rg_read_id      <= request.id;
            rg_read_error   <= request.burst_type != INCR || request.burst_size != B4 || request.addr[1:0] != 0;
        end else if(pw_read) begin
            rg_read_left    <= rg_read_left - 1;
            rg_read_address <= rg_read_address + 4;
        end
        if(w_write.wget matches tagged Valid .request) begin
            rg_write_left    <= zeroExtend(request.burst_length) + 1;
            rg_write_address <= request.addr;
            rg_write_id      <= request.id;
            rg_write_error   <= request.burst_type != INCR || request.burst_size != B4 || request.addr[1:0] != 0;
        end else if(pw_write) begin
            rg_write_left    <= rg_write_left - 1;
            rg_write_address <= rg_write_address + 4;
            if(rg_write_address >= 147456) rg_write_error <= True;
        end
    endrule

    interface s_rd = i_rd.fab;
    interface s_wr = i_wr.fab;
endmodule

endpackage
