package SimRAM_AXI;

//standard lib imports
import GetPut :: *;

import AXI4_Types :: *;
import AXI4_Slave :: *;

//custom imports
import PrintUtil :: *;
import BDPI :: *;
import SimRAM :: *;

interface SimRAM_AXI4_ifc#(numeric type sz, numeric type addrw, numeric type dataw, numeric type idw, numeric type usrw);
    interface AXI4_Slave_Rd_Fab#(addrw, dataw, idw, usrw) fab_rd;
    interface AXI4_Slave_Wr_Fab#(addrw, dataw, idw, usrw) fab_wr;
    method UInt#(64) ram_instance();
endinterface

//dataw is both the AXI data width and the RAM word width.
//addrw may be narrower than 64 bits; addresses are zero-extended for the C++ backend.
module mkSimRAM_AXI#(Bool v)(SimRAM_AXI4_ifc#(sz, addrw, dataw, idw, usrw))
    provisos(
        Add#(addrw, _pad_a, 64),            // addrw <= 64
        Add#(dataw, _pad_d, 64),            // dataw <= 64
        Add#(TDiv#(dataw, 8), _pad_s, 64)   // strobe fits in 64
    );

    function print_fmt = print_mod_pre_color_t_f;

    Integer bytes_per_word = valueof(TDiv#(dataw, 8));
    Integer addr_shift = valueof(TLog#(TDiv#(dataw, 8)));

    AXI4_Slave_Rd#(addrw, dataw, idw, usrw) slave_rd();
    mkAXI4_Slave_Rd#(8, 8) _internal_rd(slave_rd);

    AXI4_Slave_Wr#(addrw, dataw, idw, usrw) slave_wr();
    mkAXI4_Slave_Wr#(8, 8, 8) _internal_wr(slave_wr);

    SimRAMSimple_ifc m_backend <- mkSimRAM_simple;

    Reg#(UInt#(9)) transfers_left <- mkReg(0);
    Reg#(Bit#(addrw)) cur_addr <- mkRegU;
    Reg#(Bit#(idw)) cur_id_read <- mkRegU;

    Reg#(Bool) init <- mkReg(False);

    //rule to initialize c++ memory model
    rule rinit (!init);
        let ptr <- create_SimRAM(fromInteger(valueof(sz)), fromInteger(bytes_per_word));
        m_backend.set_ram(ptr);
        init <= True;
    endrule

    rule rprocess_rd_rq (transfers_left == 0 && init);
        let rrq <- slave_rd.request.get();
        transfers_left <= extend(rrq.burst_length) + 1;
        cur_addr <= rrq.addr >> fromInteger(addr_shift);
        cur_id_read <= rrq.id;

        if(rrq.burst_type != INCR)
            print_fmt($format("WARNING: Unsupported burst_type %0d, only INCR is supported", pack(rrq.burst_type)), RED);

        UInt#(32) bytes_in_transfer = fromInteger(bytes_per_word) * (extend(rrq.burst_length) + 1);
        if(v)
            print_fmt($format("Incoming Read Request for %h, bytes: ", rrq.addr, bytes_in_transfer), YELLOW);
    endrule

    rule rprocess_rd_burst (transfers_left != 0 && init);
        transfers_left <= transfers_left - 1;
        cur_addr <= cur_addr + 1;

        let rd_val <- m_backend.read(unpack(extend(cur_addr)));
        Bit#(dataw) from_memory = truncate(pack(rd_val));

        slave_rd.response.put(AXI4_Read_Rs { id: cur_id_read, data: from_memory, resp: OKAY, last: (transfers_left == 1), user: 0});
    endrule

    Reg#(UInt#(9))    transfers_left_write <- mkReg(0);
    Reg#(Bit#(addrw)) cur_addrw <- mkRegU;
    Reg#(Bit#(idw))   cur_id_write <- mkRegU;

    rule rprocess_wr_rq (transfers_left_write == 0 && init);
        let wrq_addr <- slave_wr.request_addr.get();
        transfers_left_write <= extend(wrq_addr.burst_length) + 1;
        cur_id_write <= wrq_addr.id;

        if(wrq_addr.burst_type != INCR)
            print_fmt($format("WARNING: Unsupported burst_type %0d, only INCR is supported", pack(wrq_addr.burst_type)), RED);

        UInt#(32) bytes_in_transfer = fromInteger(bytes_per_word) * (extend(wrq_addr.burst_length) + 1);

        cur_addrw <= wrq_addr.addr >> fromInteger(addr_shift);
        if(v)
            print_fmt($format("Incoming Write Request for: %h, bytes: %d", wrq_addr.addr, bytes_in_transfer), YELLOW);
    endrule

    rule rprocess_wr_burst (transfers_left_write != 0 && init);
        transfers_left_write <= transfers_left_write - 1;
        cur_addrw <= cur_addrw + 1;

        let wrq_data <- slave_wr.request_data.get;

        if(wrq_data.strb == unpack(-1))
            m_backend.write(unpack(extend(cur_addrw)), unpack(extend(wrq_data.data)));
        else if(wrq_data.strb != 0)
            m_backend.write_strobe(unpack(extend(cur_addrw)), unpack(extend(wrq_data.data)), unpack(extend(wrq_data.strb)));
        //strb == 0 means no bytes valid, skip write

        if(transfers_left_write == 1)
            slave_wr.response.put(AXI4_Write_Rs { id: cur_id_write, resp: OKAY, user: 0 });
    endrule

    method ram_instance = m_backend.get_ram;

    interface fab_rd = slave_rd.fab;
    interface fab_wr = slave_wr.fab;

endmodule

endpackage