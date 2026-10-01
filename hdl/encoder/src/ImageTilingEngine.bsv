package ImageTilingEngine;

import BRAM :: *;
import DefaultValue :: *;
import Vector :: *;
import FIFO :: *;
import GetPut :: *;

import Types :: *;
import PrintUtil :: *;
import BankedMemory :: *;

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
    //Stop after the final block has drained so the next frame can start.
    method Action stop();
endinterface


/* A second address range overlaps filling one line group with emitting the other. */
module mkImageTilingEngine#(NumProxy#(max_img_width) _, Bool double_buffer)(ImageTilingEngine_ifc#(t, mcu_w, mcu_h))
    provisos(
        Bits#(t, bpp),
        Mul#(max_img_width, mcu_h, buffer_capacity),
        Mul#(2, buffer_capacity, memory_capacity),
        Add#(buffer_capacity, 1, buffer_count_capacity),
        NumAlias#(buffer_addrw, TLog#(buffer_capacity)),
        NumAlias#(memory_addrw, TLog#(memory_capacity)),
        NumAlias#(buffer_countw, TLog#(buffer_count_capacity)),
        Add#(buffer_addrw, memory_addr_extra__, memory_addrw),
        Add#(buffer_addrw, buffer_count_extra__, buffer_countw),
        Add#(line_w, line_count_extra__, buffer_countw),
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
    Integer active_buffers = double_buffer ? 2 : 1;
    Integer memory_pixels  = active_buffers * buffered_pixels;

    BRAM_Configure bram_cfg = defaultValue;
    bram_cfg.memorySize = memory_pixels;

    FIFO#(t) f_line     <- mkFIFO;
    FIFO#(t) f_block    <- mkFIFO;

    BankedMemoryAccessor_ifc#(2, memory_addrw, bpp, 1) i_pixels <- mkBankedMemoryBRAM2Accessor(bram_cfg);

    Reg#(Bit#(line_w))          rg_imgw             <- mkRegU;
    Reg#(Bit#(buffer_countw))   rg_buf_threshold    <- mkRegU;
    Reg#(Bit#(buffer_addrw))    rg_wr_addr          <- mkRegU;
    Reg#(Bit#(buffer_addrw))    rg_rd_addr          <- mkRegU;
    Reg#(Bit#(buffer_countw))   rg_rd_pix_cnt       <- mkRegU;
    Reg#(Bit#(block_idx_w))     rg_block_idx        <- mkRegU; /* keeps track of pixel in MCU */
    Reg#(Bit#(line_w))          rg_curr_block       <- mkRegU; /* offs for current MCU in buffer */

    Reg#(Bit#(1))          rg_wr_buf    <- mkReg(0);
    Reg#(Bit#(1))          rg_rd_buf    <- mkReg(0);
    Vector#(2, Reg#(Bool)) rg_buf_ready <- replicateM(mkReg(False));

    Reg#(Bool) rg_running <- mkReg(False);

    function Bit#(memory_addrw) buffer_address(Bit#(1) buffer_index, Bit#(buffer_addrw) address);
        Bit#(memory_addrw) memory_address = zeroExtend(address);
        if(double_buffer && buffer_index == 1)
            memory_address = memory_address + fromInteger(buffered_pixels);
        return memory_address;
    endfunction

    function Action write_pixel(Bit#(1) buffer_index, Bit#(buffer_addrw) address, t pixel);
        action
            i_pixels.port[0].request(BankedMemoryRequest_t {
                address   : buffer_address(buffer_index, address),
                data      : pack(pixel),
                write_mask: 1,
                write     : True
            });
        endaction
    endfunction

    function Action read_pixel(Bit#(1) buffer_index, Bit#(buffer_addrw) address);
        action
            i_pixels.port[1].request(BankedMemoryRequest_t {
                address   : buffer_address(buffer_index, address),
                data      : 0,
                write_mask: 0,
                write     : False
            });
        endaction
    endfunction

    /*
        We start filling a new MCU when all relevant pixels have been fetched
        this could start even earlier, when (rg_imgw-1)*mcu_h+mcu_w have been fetched but 
        lets stick with the simpler calculation for now as this also alllows easier termination
        of writing to the buffer
    */

    function Action advance_write(Reg#(Bool) buffer_ready);
        action
            if(zeroExtend(rg_wr_addr) == rg_buf_threshold - 1) begin
                rg_wr_addr <= 0;
                if(double_buffer) rg_wr_buf <= ~rg_wr_buf;
                buffer_ready <= True;
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

    function Action forward_pixel(t pix);
        action
            f_block.enq(pix);
            rg_rd_pix_cnt <= rg_rd_pix_cnt - 1;
        endaction
    endfunction

    function Action finish_buffer(t pix, Reg#(Bool) buffer_ready);
        action
            f_block.enq(pix);
            rg_rd_addr      <= 0;
            rg_rd_pix_cnt   <= rg_buf_threshold;
            rg_block_idx    <= 0;
            rg_curr_block   <= 0;
            if(double_buffer) rg_rd_buf <= ~rg_rd_buf;
            buffer_ready <= False;
        endaction
    endfunction

    for(Integer buffer_index = 0; buffer_index < active_buffers; buffer_index = buffer_index + 1) begin
        rule r_drain_input (rg_running && rg_wr_buf == fromInteger(buffer_index) && !rg_buf_ready[buffer_index]);
            let pix = f_line.first;
            f_line.deq;
            advance_write(rg_buf_ready[buffer_index]);
            write_pixel(fromInteger(buffer_index), rg_wr_addr, pix);
        endrule

        rule r_process_block (rg_running && rg_rd_buf == fromInteger(buffer_index) && rg_buf_ready[buffer_index] && rg_curr_block < rg_imgw);
            advance_read_request();
            read_pixel(fromInteger(buffer_index), rg_rd_addr);
        endrule

        rule r_fwd_out (rg_running && rg_rd_buf == fromInteger(buffer_index) && rg_buf_ready[buffer_index] && rg_rd_pix_cnt > 1);
            let pix <- i_pixels.port[1].response();
            forward_pixel(unpack(pix));
        endrule

        rule r_finish_buffer (rg_running && rg_rd_buf == fromInteger(buffer_index) && rg_buf_ready[buffer_index] && rg_rd_pix_cnt == 1 && rg_curr_block >= rg_imgw);
            let pix <- i_pixels.port[1].response();
            finish_buffer(unpack(pix), rg_buf_ready[buffer_index]);
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
        for(Integer buffer_index = 0; buffer_index < 2; buffer_index = buffer_index + 1)
            rg_buf_ready[buffer_index] <= False;
    endaction;

    method Action stop();
        rg_running <= False;
    endmethod

    interface line_in   = toPut(f_line);
    interface block_out = toGet(f_block);

endmodule

endpackage
