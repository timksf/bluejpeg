package StreamFabAdapters;

import Connectable :: *;

import AXI4_Stream :: *;
import AxiStream :: *;

/*
 * Connects BlueAXI stream fabrics (AXI4_Stream_*_Fab) to the AxiStream fabrics of the
 * dual-clock FIFO. Both sides carry the same AXI4-Stream signals, only the method names
 * and the fixed BlueAXI id/dest widths differ. tid and tdest are not used by this design.
 */

instance Connectable#(AXI4_Stream_Wr_Fab#(data_w, user_w), AxiStream_Slave_Fab#(data_w, user_w, id_w, dest_w));
    module mkConnection#(AXI4_Stream_Wr_Fab#(data_w, user_w) master, AxiStream_Slave_Fab#(data_w, user_w, id_w, dest_w) slave)(Empty);
        (* fire_when_enabled, no_implicit_conditions *)
        rule r_forward;
            slave.ptvalid(master.tvalid);
            slave.ptdata(master.tdata);
            slave.ptkeep(master.tkeep);
            slave.ptuser(master.tuser);
            slave.ptid(0);
            slave.ptdest(0);
            slave.ptlast(master.tlast);
        endrule

        (* fire_when_enabled, no_implicit_conditions *)
        rule r_ready;
            master.ptready(slave.tready);
        endrule
    endmodule
endinstance

instance Connectable#(AxiStream_Master_Fab#(data_w, user_w, id_w, dest_w), AXI4_Stream_Rd_Fab#(data_w, user_w));
    module mkConnection#(AxiStream_Master_Fab#(data_w, user_w, id_w, dest_w) master, AXI4_Stream_Rd_Fab#(data_w, user_w) slave)(Empty);
        (* fire_when_enabled, no_implicit_conditions *)
        rule r_forward;
            slave.ptvalid(master.tvalid);
            slave.ptdata(master.tdata);
            slave.ptkeep(master.tkeep);
            slave.ptuser(master.tuser);
            slave.ptDest(0);
            slave.ptid(0);
            slave.ptlast(master.tlast);
        endrule

        (* fire_when_enabled, no_implicit_conditions *)
        rule r_ready;
            master.ptready(slave.tready);
        endrule
    endmodule
endinstance

endpackage
