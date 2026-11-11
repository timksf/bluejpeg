package UdpModel;

import FIFOF :: *;
import GetPut :: *;

import AXI4_Stream :: *;
import EthernetTypes :: *;
import UdpRgmiiCsr :: *;

interface UdpModel_ifc;
    interface Get#(UdpRxHeader)            rx_header;
    interface EthernetStreamSource_ifc     rx_payload;
    interface Put#(UdpTxRequest)           tx_header;
    interface EthernetStreamSink_ifc       tx_payload;
    interface Put#(UdpRxHeader)            send_header;
    interface Put#(AXI4_Stream_Pkg#(8, 1)) send_byte;
    interface Get#(UdpTxRequest)           receive_header;
    interface Get#(AXI4_Stream_Pkg#(8, 1)) receive_byte;
    method Action                          hold_tx(Bool hold);
endinterface

module mkUdpModel(UdpModel_ifc);
    FIFOF#(UdpRxHeader)   f_rx_headers <- mkFIFOF;
    FIFOF#(UdpTxRequest)  f_tx_headers <- mkFIFOF;
    AXI4_Stream_Wr#(8, 1) i_rx         <- mkAXI4_Stream_Wr(2);
    AXI4_Stream_Rd#(8, 1) i_tx         <- mkAXI4_Stream_Rd(2);
    Reg#(Bit#(4))         rg_phase     <- mkReg(0);
    Reg#(Bool)            rg_hold      <- mkReg(False);
    Bool                  ready        = !rg_hold && rg_phase < 11;
    rule r_phase;
        rg_phase <= rg_phase + 1;
    endrule
    interface rx_header  = toGet(f_rx_headers);
    interface rx_payload = i_rx.fab;
    interface tx_header  = toPut(f_tx_headers);
    interface EthernetStreamSink_ifc tx_payload;
        method tready = ready && i_tx.fab.tready;
        method Action ptvalid(Bool valid);
            i_tx.fab.ptvalid(valid && ready);
        endmethod
        method ptdata = i_tx.fab.ptdata;
        method ptuser = i_tx.fab.ptuser;
        method ptkeep = i_tx.fab.ptkeep;
        method ptDest = i_tx.fab.ptDest;
        method ptid   = i_tx.fab.ptid;
        method ptlast = i_tx.fab.ptlast;
    endinterface
    interface send_header    = toPut(f_rx_headers);
    interface send_byte      = i_rx.pkg;
    interface receive_header = toGet(f_tx_headers);
    interface receive_byte   = i_tx.pkg;
    method Action hold_tx(Bool hold);
        rg_hold <= hold;
    endmethod
endmodule

endpackage
