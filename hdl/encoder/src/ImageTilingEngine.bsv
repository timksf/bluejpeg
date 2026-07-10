package ImageTilingEngine;

import BRAM :: *;
import DefaultValue :: *;
import ClientServer :: *;
import Vector :: *;
import FIFO :: *;
import GetPut :: *;

import Types :: *;
import PrintUtil :: *;
import Util :: *;

/*

    We could use AXI Stream between all the processing modules but this would probably 
    cause unnecessary overhead. So instead, simply use Bluespecs handshaking between modules
    with Clients and Servers.
    For this Tiling Engine, there should be an AXI Stream adapter, since it will directly be connected
    to the outside world. 
    This adapter can also be implemented in the actual Encoder, however.

*/

interface ImageTilingEngine_ifc#(type t, numeric type mcu_w, numeric type mcu_h);
    interface Put#(t) line_in;
    interface Get#(t) block_out;

    method Action set_img_width(Bit#(13) x);
    method Action start();
endinterface


/* A second BRAM bank overlaps filling one line group with emitting the other. */
module mkImageTilingEngine#(NumProxy#(max_img_width) _, Bool double_buffer)(ImageTilingEngine_ifc#(t, mcu_w, mcu_h))
    provisos(
        Bits#(t, bpp),
        Mul#(max_img_width, mcu_h, buffer_capacity),
        NumAlias#(buffer_addrw, TLog#(buffer_capacity)),
        Add#(a__, TLog#(TDiv#(line_w, mcu_w)), buffer_addrw),
        NumAlias#(line_w, TLog#(max_img_width)),
        Add#(b__, line_w, 13),
        Add#(c__, line_w, buffer_addrw),
        Mul#(mcu_w, mcu_h, pixels_in_mcu),
        Log#(pixels_in_mcu, block_idx_w),
        Log#(mcu_w, log2_mcu_w)
        // Add#(TExp#(log2_mcu_w), 0, mcu_w),
        // Log#(mcu_h, log2_mcu_h),
        // Add#(TExp#(log2_mcu_h), 0, mcu_h)
    );

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    /* required BRAM capacity is calculated from max. upported scanline width and MCU height */
    Integer buffered_pixels = valueof(buffer_capacity);
    Integer pixels_per_block = valueof(pixels_in_mcu);

    BRAM_Configure cfg = defaultValue;
    cfg.memorySize = buffered_pixels;

    FIFO#(t) f_line     <- mkFIFO;
    FIFO#(t) f_block    <- mkFIFO;

    BRAM1Port#(Bit#(buffer_addrw), t) bram_pixels0 <- mkBRAM1Server(cfg);
    BRAM1Port#(Bit#(buffer_addrw), t) bram_pixels1 = ?;
    if(double_buffer) begin
        bram_pixels1 <- mkBRAM1Server(cfg);
    end

    Reg#(Bit#(line_w))          rg_imgw             <- mkRegU;
    Reg#(Bit#(buffer_addrw))    rg_buf_threshold    <- mkRegU;
    Reg#(Bit#(buffer_addrw))    rg_wr_addr          <- mkRegU;
    Reg#(Bit#(buffer_addrw))    rg_rd_addr          <- mkRegU;
    Reg#(Bit#(buffer_addrw))    rg_rd_pix_cnt       <- mkRegU;
    Reg#(Bit#(block_idx_w))     rg_block_idx        <- mkRegU; /* keeps track of pixel in MCU */
    Reg#(Bit#(line_w))          rg_curr_block       <- mkRegU; /* offs for current MCU in buffer */

    Reg#(Bit#(1)) rg_wr_buf <- mkReg(0);
    Reg#(Bit#(1)) rg_rd_buf <- mkReg(0);

    Reg#(Bool) rg_buf0_ready <- mkReg(False);
    Reg#(Bool) rg_buf1_ready <- mkReg(False);

    Reg#(Bool) rg_running     <- mkReg(False);
    Reg#(Bool) rg_rewind_read <- mkReg(False);

    /*
        We start filling a new MCU when all relevant pixels have been fetched
        this could start even earlier, when (rg_imgw-1)*mcu_h+mcu_w have been fetched but 
        lets stick with the simpler calculation for now as this also alllows easier termination
        of writing to the buffer
    */

    function Action advance_write(Bit#(1) bank);
        action
            if(rg_wr_addr == rg_buf_threshold - 1) begin
                rg_wr_addr <= 0;
                if(double_buffer) rg_wr_buf <= ~rg_wr_buf;
                if(bank == 0) rg_buf0_ready <= True;
                else          rg_buf1_ready <= True;
            end else begin
                rg_wr_addr <= rg_wr_addr + 1;
            end
        endaction
    endfunction

    /*
        When the buffer is full, we will be able to dispatch line_width / mcu_width blocks
        each block is fetched from the buffer sequentially, so we need to keep track of the current block
        and the current index inside of the respective block while also modifying the 
        buffer address correctly
    */
    function Action advance_read_request();
        action
            let next_addr = rg_rd_addr;
            if((rg_block_idx & fromInteger(valueof(mcu_w) - 1)) == fromInteger(valueof(mcu_w) - 1)) begin
                /* move to next scanline */
                next_addr = next_addr + zeroExtend(rg_imgw) - fromInteger(valueof(mcu_w)) + 1;
            end else begin
                next_addr = next_addr + 1;
            end
            if(rg_block_idx == fromInteger(pixels_per_block - 1)) begin
                /* move to start of next block */
                let next_block_offs = rg_curr_block + fromInteger(valueof(mcu_w));
                next_addr = zeroExtend(next_block_offs);
                rg_curr_block <= next_block_offs;
            end
            rg_block_idx <= rg_block_idx + 1;
            rg_rd_addr   <= next_addr;
        endaction
    endfunction

    function Action forward_pixel(t pix, Bit#(1) bank);
        action
            f_block.enq(pix);
            if(rg_rd_pix_cnt == 1) begin
                rg_rd_pix_cnt <= rg_buf_threshold;
                rg_rewind_read <= True;
                if(double_buffer) rg_rd_buf <= ~rg_rd_buf;
                if(bank == 0) rg_buf0_ready <= False;
                else          rg_buf1_ready <= False;
            end else begin
                rg_rd_pix_cnt <= rg_rd_pix_cnt - 1;
            end
        endaction
    endfunction

    rule r_rewind_read (rg_running && rg_rewind_read);
        rg_rd_addr     <= 0;
        rg_block_idx   <= 0;
        rg_curr_block  <= 0;
        rg_rewind_read <= False;
    endrule

    if(double_buffer) begin
        rule r_drain_input0 (rg_running && rg_wr_buf == 0 && !rg_buf0_ready);
            let pix = f_line.first;
            f_line.deq;
            advance_write(0);
            write_to_bram(bram_pixels0.portA, rg_wr_addr, pix);
        endrule

        rule r_drain_input1 (rg_running && rg_wr_buf == 1 && !rg_buf1_ready);
            let pix = f_line.first;
            f_line.deq;
            advance_write(1);
            write_to_bram(bram_pixels1.portA, rg_wr_addr, pix);
        endrule

        rule r_process_block0 (rg_running && !rg_rewind_read && rg_rd_buf == 0 && rg_buf0_ready && rg_curr_block < rg_imgw);
            advance_read_request();
            read_req_to_bram(bram_pixels0.portA, rg_rd_addr);
        endrule

        rule r_process_block1 (rg_running && !rg_rewind_read && rg_rd_buf == 1 && rg_buf1_ready && rg_curr_block < rg_imgw);
            advance_read_request();
            read_req_to_bram(bram_pixels1.portA, rg_rd_addr);
        endrule

        rule r_fwd_out0 (rg_running && !rg_rewind_read && rg_rd_buf == 0 && rg_buf0_ready && rg_rd_pix_cnt > 0);
            let pix <- bram_pixels0.portA.response.get();
            forward_pixel(pix, 0);
        endrule

        rule r_fwd_out1 (rg_running && !rg_rewind_read && rg_rd_buf == 1 && rg_buf1_ready && rg_rd_pix_cnt > 0);
            let pix <- bram_pixels1.portA.response.get();
            forward_pixel(pix, 1);
        endrule
    end else begin
        rule r_drain_input (rg_running && !rg_buf0_ready);
            let pix = f_line.first;
            f_line.deq;
            advance_write(0);
            write_to_bram(bram_pixels0.portA, rg_wr_addr, pix);
        endrule

        rule r_process_block (rg_running && !rg_rewind_read && rg_buf0_ready && rg_curr_block < rg_imgw);
            advance_read_request();
            read_req_to_bram(bram_pixels0.portA, rg_rd_addr);
        endrule

        rule r_fwd_out (rg_running && !rg_rewind_read && rg_buf0_ready && rg_rd_pix_cnt > 0);
            let pix <- bram_pixels0.portA.response.get();
            forward_pixel(pix, 0);
        endrule
    end

    method Action set_img_width(Bit#(13) w) = action
        Bit#(line_w) w_trunc = truncate(w);
        rg_imgw <= w_trunc;
        rg_buf_threshold <= zeroExtend(w_trunc) * fromInteger(valueof(mcu_h));
    endaction;
    
    method start if(!rg_running) = action
        rg_running         <= True;
        rg_wr_addr         <= 0;
        rg_rd_addr         <= 0;
        rg_rd_pix_cnt      <= rg_buf_threshold;
        rg_block_idx       <= 0;
        rg_curr_block      <= 0;
        rg_wr_buf          <= 0;
        rg_rd_buf          <= 0;
        rg_buf0_ready      <= False;
        rg_buf1_ready      <= False;
        rg_rewind_read     <= False;
    endaction;

    interface line_in   = toPut(f_line);
    interface block_out = toGet(f_block);

endmodule

endpackage
