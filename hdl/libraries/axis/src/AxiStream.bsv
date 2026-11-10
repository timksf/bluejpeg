package AxiStream;

import Connectable :: *;

typedef struct {
    Bit#(data_w)          data;
    Bit#(TDiv#(data_w, 8)) keep;
    Bit#(user_w)          user;
    Bit#(id_w)            id;
    Bit#(dest_w)          dest;
    Bool                  last;
} AxiStreamPayload_t#(
    numeric type data_w,
    numeric type user_w,
    numeric type id_w,
    numeric type dest_w
) deriving(Bits, Eq, FShow);

/*
 * Fabric input port. Signal methods are deliberately unguarded so the
 * generated RTL presents a conventional AXI Stream slave interface.
 */
(* always_ready, always_enabled *)
interface AxiStream_Slave_Fab#(
    numeric type data_w,
    numeric type user_w,
    numeric type id_w,
    numeric type dest_w
);
    method Bool tready;
    (* prefix = "" *) method Action ptvalid((* port = "tvalid" *) Bool valid);
    (* prefix = "" *) method Action ptdata((* port = "tdata" *) Bit#(data_w) data);
    (* prefix = "" *) method Action ptkeep((* port = "tkeep" *) Bit#(TDiv#(data_w, 8)) keep);
    (* prefix = "" *) method Action ptuser((* port = "tuser" *) Bit#(user_w) user);
    (* prefix = "" *) method Action ptid((* port = "tid" *) Bit#(id_w) id);
    (* prefix = "" *) method Action ptdest((* port = "tdest" *) Bit#(dest_w) dest);
    (* prefix = "" *) method Action ptlast((* port = "tlast" *) Bool last);
endinterface

/*
 * Fabric output port. Signal methods are deliberately unguarded so the
 * generated RTL presents a conventional AXI Stream master interface.
 */
(* always_ready, always_enabled *)
interface AxiStream_Master_Fab#(
    numeric type data_w,
    numeric type user_w,
    numeric type id_w,
    numeric type dest_w
);
    method Bool tvalid;
    (* prefix = "" *) method Action ptready((* port = "tready" *) Bool ready);
    method Bit#(data_w) tdata;
    method Bit#(TDiv#(data_w, 8)) tkeep;
    method Bit#(user_w) tuser;
    method Bit#(id_w) tid;
    method Bit#(dest_w) tdest;
    method Bool tlast;
endinterface

instance Connectable#(
    AxiStream_Master_Fab#(data_w, user_w, id_w, dest_w),
    AxiStream_Slave_Fab#(data_w, user_w, id_w, dest_w)
);
    module mkConnection#(
            AxiStream_Master_Fab#(data_w, user_w, id_w, dest_w) master,
            AxiStream_Slave_Fab#(data_w, user_w, id_w, dest_w) slave
        )(Empty);

        rule r_connect_forward;
            slave.ptvalid(master.tvalid);
            slave.ptdata(master.tdata);
            slave.ptkeep(master.tkeep);
            slave.ptuser(master.tuser);
            slave.ptid(master.tid);
            slave.ptdest(master.tdest);
            slave.ptlast(master.tlast);
        endrule

        rule r_connect_ready;
            master.ptready(slave.tready);
        endrule

    endmodule
endinstance

instance Connectable#(
    AxiStream_Slave_Fab#(data_w, user_w, id_w, dest_w),
    AxiStream_Master_Fab#(data_w, user_w, id_w, dest_w)
);
    module mkConnection#(
            AxiStream_Slave_Fab#(data_w, user_w, id_w, dest_w) slave,
            AxiStream_Master_Fab#(data_w, user_w, id_w, dest_w) master
        )(Empty);

        mkConnection(master, slave);

    endmodule
endinstance

endpackage
