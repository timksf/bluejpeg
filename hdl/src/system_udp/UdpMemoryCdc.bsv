package UdpMemoryCdc;

import Clocks :: *;
import Connectable :: *;
import GetPut :: *;
import AXI4_Master :: *;
import AXI4_Slave :: *;
import AXI4_Types :: *;

interface UdpMemoryCdc_ifc;
    interface AXI4_Slave_Rd_Fab#(30, 32, 4, 0)  s_rd;
    interface AXI4_Slave_Wr_Fab#(30, 32, 4, 0)  s_wr;
    interface AXI4_Master_Rd_Fab#(30, 32, 4, 0) m_rd;
    interface AXI4_Master_Wr_Fab#(30, 32, 4, 0) m_wr;
endinterface

/*
 * Five independent AXI channels cross between the application and memory clocks.
 * Both domains must reset together. The caller supplies the memory-side reset
 * synchronized from the application reset. Bursts and responses retain ordering.
 */
module mkUdpMemoryCdc#(Clock clk_mem, Reset rst_mem)(UdpMemoryCdc_ifc);
    AXI4_Slave_Rd#(30, 32, 4, 0)  i_slave_rd  <- mkAXI4_Slave_Rd(2, 2);
    AXI4_Slave_Wr#(30, 32, 4, 0)  i_slave_wr  <- mkAXI4_Slave_Wr(2, 2, 2);
    AXI4_Master_Rd#(30, 32, 4, 0) i_master_rd <- mkAXI4_Master_Rd(2, 2, False, clocked_by clk_mem, reset_by rst_mem);
    AXI4_Master_Wr#(30, 32, 4, 0) i_master_wr <- mkAXI4_Master_Wr(2, 2, 2, False, clocked_by clk_mem, reset_by rst_mem);

    SyncFIFOIfc#(AXI4_Read_Rq#(30, 4, 0))       f_ar <- mkSyncFIFOFromCC(4, clk_mem);
    SyncFIFOIfc#(AXI4_Read_Rs#(32, 4, 0))       f_r  <- mkSyncFIFOToCC(32, clk_mem, rst_mem);
    SyncFIFOIfc#(AXI4_Write_Rq_Addr#(30, 4, 0)) f_aw <- mkSyncFIFOFromCC(4, clk_mem);
    SyncFIFOIfc#(AXI4_Write_Rq_Data#(32, 0))    f_w  <- mkSyncFIFOFromCC(4, clk_mem);
    SyncFIFOIfc#(AXI4_Write_Rs#(4, 0))          f_b  <- mkSyncFIFOToCC(4, clk_mem, rst_mem);

    mkConnection(i_slave_rd.request,      toPut(f_ar));
    mkConnection(toGet(f_ar),             i_master_rd.request);
    mkConnection(i_master_rd.response,    toPut(f_r));
    mkConnection(toGet(f_r),              i_slave_rd.response);
    mkConnection(i_slave_wr.request_addr, toPut(f_aw));
    mkConnection(toGet(f_aw),             i_master_wr.request_addr);
    mkConnection(i_slave_wr.request_data, toPut(f_w));
    mkConnection(toGet(f_w),              i_master_wr.request_data);
    mkConnection(i_master_wr.response,    toPut(f_b));
    mkConnection(toGet(f_b),              i_slave_wr.response);

    interface s_rd = i_slave_rd.fab;
    interface s_wr = i_slave_wr.fab;
    interface m_rd = i_master_rd.fab;
    interface m_wr = i_master_wr.fab;
endmodule

endpackage
