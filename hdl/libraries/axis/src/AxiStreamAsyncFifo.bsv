package AxiStreamAsyncFifo;

import Clocks :: *;

import AxiStream :: *;

interface AxiStreamAsyncFifo_ifc#(
    numeric type data_w,
    numeric type user_w,
    numeric type id_w,
    numeric type dest_w
);
    (* prefix = "S_AXIS" *)
    interface AxiStream_Slave_Fab#(data_w, user_w, id_w, dest_w) s_axis;

    (* prefix = "M_AXIS" *)
    interface AxiStream_Master_Fab#(data_w, user_w, id_w, dest_w) m_axis;
endinterface

/*
 * Dual-clock AXI Stream FIFO. The Bluespec synchronizer resets from the
 * source domain and safely propagates its empty/full state across both clock
 * domains. No extra registered empty/full stage is enabled.
 */
module mkAxiStreamAsyncFifo#(
        Integer depth,
        Clock s_clock,
        Reset s_reset,
        Clock m_clock
    )(AxiStreamAsyncFifo_ifc#(data_w, user_w, id_w, dest_w))
    provisos(
        Div#(data_w, 8, keep_w)
    );

    SyncFIFOIfc#(AxiStreamPayload_t#(data_w, user_w, id_w, dest_w)) f_data <-
        mkSyncFIFO(depth, s_clock, s_reset, m_clock);

    Wire#(Bool) w_s_valid <- mkDWire(False, clocked_by s_clock, reset_by s_reset);

    Wire#(Bit#(data_w)) w_s_data <- mkDWire(0, clocked_by s_clock, reset_by s_reset);
    Wire#(Bit#(keep_w)) w_s_keep <- mkDWire(0, clocked_by s_clock, reset_by s_reset);
    Wire#(Bit#(user_w)) w_s_user <- mkDWire(0, clocked_by s_clock, reset_by s_reset);
    Wire#(Bit#(id_w))   w_s_id   <- mkDWire(0, clocked_by s_clock, reset_by s_reset);
    Wire#(Bit#(dest_w)) w_s_dest <- mkDWire(0, clocked_by s_clock, reset_by s_reset);
    Wire#(Bool)         w_s_last <- mkDWire(False, clocked_by s_clock, reset_by s_reset);

    Wire#(Bool) w_m_ready <- mkDWire(False, clocked_by m_clock, reset_by noReset);

    Wire#(Bit#(data_w)) w_m_data <- mkDWire(0, clocked_by m_clock, reset_by noReset);
    Wire#(Bit#(keep_w)) w_m_keep <- mkDWire(0, clocked_by m_clock, reset_by noReset);
    Wire#(Bit#(user_w)) w_m_user <- mkDWire(0, clocked_by m_clock, reset_by noReset);
    Wire#(Bit#(id_w))   w_m_id   <- mkDWire(0, clocked_by m_clock, reset_by noReset);
    Wire#(Bit#(dest_w)) w_m_dest <- mkDWire(0, clocked_by m_clock, reset_by noReset);
    Wire#(Bool)         w_m_last <- mkDWire(False, clocked_by m_clock, reset_by noReset);

    rule r_enqueue (w_s_valid);
        f_data.enq(AxiStreamPayload_t {
            data: w_s_data,
            keep: w_s_keep,
            user: w_s_user,
            id  : w_s_id,
            dest: w_s_dest,
            last: w_s_last
        });
    endrule

    rule r_present;
        let payload = f_data.first;
        w_m_data <= payload.data;
        w_m_keep <= payload.keep;
        w_m_user <= payload.user;
        w_m_id   <= payload.id;
        w_m_dest <= payload.dest;
        w_m_last <= payload.last;
    endrule

    rule r_dequeue (w_m_ready);
        f_data.deq;
    endrule

    interface AxiStream_Slave_Fab s_axis;
        method Bool tready = f_data.notFull;
        method Action ptvalid(Bool valid);
            w_s_valid <= valid;
        endmethod
        method Action ptdata(Bit#(data_w) data);
            w_s_data <= data;
        endmethod
        method Action ptkeep(Bit#(keep_w) keep);
            w_s_keep <= keep;
        endmethod
        method Action ptuser(Bit#(user_w) user);
            w_s_user <= user;
        endmethod
        method Action ptid(Bit#(id_w) id);
            w_s_id <= id;
        endmethod
        method Action ptdest(Bit#(dest_w) dest);
            w_s_dest <= dest;
        endmethod
        method Action ptlast(Bool last);
            w_s_last <= last;
        endmethod
    endinterface

    interface AxiStream_Master_Fab m_axis;
        method Bool tvalid = f_data.notEmpty;
        method Action ptready(Bool ready);
            w_m_ready <= ready;
        endmethod
        method Bit#(data_w) tdata = w_m_data;
        method Bit#(keep_w) tkeep = w_m_keep;
        method Bit#(user_w) tuser = w_m_user;
        method Bit#(id_w) tid = w_m_id;
        method Bit#(dest_w) tdest = w_m_dest;
        method Bool tlast = w_m_last;
    endinterface

endmodule

endpackage