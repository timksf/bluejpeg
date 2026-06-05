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
    method Action set_img_size(Bit#(13) w, Bit#(13) h);
    method Action start();
endinterface


module mkImageTilingEngine#(NumProxy#(max_img_width) _)(ImageTilingEngine_ifc#(t, mcu_w, mcu_h))
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

    BRAM1Port#(Bit#(buffer_addrw), t) bram_pixels <- mkBRAM1Server(cfg);

    Reg#(Bit#(line_w))          rg_imgw             <- mkRegU;
    Reg#(Bit#(buffer_addrw))    rg_buf_threshold    <- mkRegU;
    Reg#(Bit#(buffer_addrw))    rg_pix_cnt          <- mkRegU;
    Reg#(Bit#(buffer_addrw))    rg_buf_addr         <- mkRegU; /* address for writing to/reading from buffer */
    Reg#(Bit#(block_idx_w))     rg_block_idx        <- mkRegU; /* keeps track of pixel in MCU */
    Reg#(Bit#(line_w))          rg_curr_block       <- mkRegU; /* offs for current MCU in buffer */
    Reg#(Bit#(13))              rg_frame_stripes    <- mkReg(0);
    Reg#(Bit#(13))              rg_stripe_idx       <- mkReg(0);

    Reg#(Bool) rg_running   <- mkReg(False);
    Reg#(Bool) rg_output    <- mkRegU;

    /*
        We start filling a new MCU when all relevant pixels have been fetched
        this could start even earlier, when (rg_imgw-1)*mcu_h+mcu_w have been fetched but 
        lets stick with the simpler calculation for now as this also alllows easier termination
        of writing to the buffer
    */

    /* Fill the buffer RAM with pixels */
    rule r_drain_input if(rg_running && rg_pix_cnt < rg_buf_threshold && !rg_output);
        let pix = f_line.first;
        f_line.deq;
        rg_pix_cnt <= rg_pix_cnt + 1;
        if(rg_pix_cnt == rg_buf_threshold - 1) begin
            /* buffer is now full, start building MCUs */
            rg_block_idx    <= 0;
            rg_buf_addr     <= 0;
            rg_curr_block   <= 0;
            rg_output       <= True;
        end else begin
            rg_buf_addr     <= rg_buf_addr + 1;
        end
        /* send write request for current pixel to BRAM controller */
        write_to_bram(bram_pixels.portA, rg_buf_addr, pix);
        // print_fmt($format("Writing %0X to BRAM at %0d", pix, rg_buf_addr), YELLOW);
    endrule

    /*
        When the buffer is full, we will be able to dispatch line_width / mcu_width blocks
        each block is fetched from the buffer sequentially, so we need to keep track of the current block
        and the current index inside of the respective block while also modifying the 
        buffer address correctly
    */
    rule r_process_block if(rg_running && rg_output && rg_curr_block < rg_imgw);
        /* for debugging purposes */
        let block_x = rg_block_idx % fromInteger(valueof(mcu_w));
        let block_y = rg_block_idx / fromInteger(valueof(mcu_w));

        // print_fmt($format("Block %0d X %0d Y %0d Addr ", rg_curr_block>>fromInteger(valueof(log2_mcu_w)), block_x, block_y, rg_buf_addr), YELLOW);

        let next_addr = rg_buf_addr;
        if((rg_block_idx & fromInteger(valueof(mcu_w) - 1)) == fromInteger(valueof(mcu_w) - 1)) begin
            /* move to next scanline */
            next_addr = next_addr + zeroExtend(rg_imgw) - fromInteger(valueof(mcu_w)) + 1;
        end else begin
            next_addr = next_addr + 1;
        end
        if(rg_block_idx == fromInteger(pixels_per_block-1)) begin
            /* move to start of next block */
            let next_block_offs = rg_curr_block + fromInteger(valueof(mcu_w));
            next_addr = zeroExtend(next_block_offs);
            rg_curr_block <= next_block_offs;
        end
        rg_block_idx <= rg_block_idx + 1;
        rg_buf_addr <= next_addr;

        /* dispatch read request for current pixel */
        read_req_to_bram(bram_pixels.portA, rg_buf_addr);
    endrule

    /* Forward BRAM read results to output fifo */
    rule r_fwd_out if(rg_running && rg_output && rg_pix_cnt > 0);
        let pix <- bram_pixels.portA.response.get();
        f_block.enq(pix);
        rg_pix_cnt <= rg_pix_cnt - 1;
    endrule

    rule r_finish if(rg_running && rg_output && rg_pix_cnt == 0 && rg_curr_block >= rg_imgw);
        // print_s("Finished processing", BLUE);
        rg_pix_cnt  <= 0;
        rg_buf_addr <= 0;
        rg_output   <= False;

        if(rg_frame_stripes != 0 && rg_stripe_idx == rg_frame_stripes - 1) begin
            rg_running    <= False;
            rg_stripe_idx <= 0;
        end else begin
            rg_stripe_idx <= rg_stripe_idx + 1;
        end
    endrule

    function Action configure(Bit#(13) w, Bit#(13) h);
        action
            Bit#(line_w) w_trunc = truncate(w);
            Bit#(13) stripes = 0;

            if(h != 0)
                stripes = (h + fromInteger(valueof(mcu_h) - 1)) / fromInteger(valueof(mcu_h));

            rg_imgw <= w_trunc;
            rg_buf_threshold <= zeroExtend(w_trunc) * fromInteger(valueof(mcu_h));
            rg_frame_stripes <= stripes;
            rg_stripe_idx <= 0;
        endaction
    endfunction

    method Action set_img_width(Bit#(13) w) = action
        Bit#(line_w) w_trunc = truncate(w);
        rg_imgw <= w_trunc;
        rg_buf_threshold <= zeroExtend(w_trunc) * fromInteger(valueof(mcu_h));
        rg_frame_stripes <= 0;
        rg_stripe_idx <= 0;
    endaction;

    method Action set_img_size(Bit#(13) w, Bit#(13) h) = configure(w, h);
    
    method start if(!rg_running) = action
        rg_running  <= True;
        rg_pix_cnt  <= 0;
        rg_buf_addr <= 0;
        rg_output   <= False;
    endaction;

    interface line_in   = toPut(f_line);
    interface block_out = toGet(f_block);

endmodule

endpackage
