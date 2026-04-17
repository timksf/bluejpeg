package ChromaSubsampler;

import FIFO :: *;
import GetPut :: *;
import SpecialFIFOs :: *;
import RegFile :: *;
import BRAM :: *;

import Types :: *;
import PrintUtil :: *;

interface ChromaSubsampler_ifc#(numeric type max_img_width);
    method Action configure(SubsamplingMode_t mode, Bit#(13) img_width);
    method Action rewind();
    
    interface Put#(UInt#(8)) pixel_in;
    interface Get#(UInt#(8)) pixel_out;
endinterface

module mkChromaSubsampler#(Bool use_bram)(ChromaSubsampler_ifc#(max_img_width))
    provisos(
        NumAlias#(line_addr_w, TLog#(TDiv#(max_img_width, 2))),
        Add#(a__, line_addr_w, 13)
    );

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    FIFO#(UInt#(8)) f_in  <- mkPipelineFIFO;
    FIFO#(UInt#(8)) f_out <- mkPipelineFIFO;

    //configuration
    Reg#(SubsamplingMode_t) rg_mode         <- mkReg(YCBCR_444);
    Reg#(Bit#(13))          rg_img_width    <- mkReg(0);

    //state
    Reg#(Bit#(13))  rg_col      <- mkReg(0);
    Reg#(Bool)      rg_row_odd  <- mkReg(False);
    Reg#(UInt#(8))  rg_prev     <- mkRegU;

    //average two 8-bit values with rounding
    function UInt#(8) avg2(UInt#(8) a, UInt#(8) b);
        UInt#(9) sum = zeroExtend(a) + zeroExtend(b) + 1;
        return truncate(sum >> 1);
    endfunction

    Bool col_odd = rg_col[0] == 1;
    Bit#(line_addr_w) pair_idx = truncate(rg_col >> 1);

    function Action advance_col();
        return action
            if (rg_col == rg_img_width - 1) begin
                rg_col     <= 0;
                rg_row_odd <= !rg_row_odd;
            end else begin
                rg_col <= rg_col + 1;
            end
        endaction;
    endfunction

    //4:4:4 -> passthrough
    rule r_444 (rg_mode == YCBCR_444);
        let px = f_in.first; f_in.deq;
        f_out.enq(px);
    endrule

    //4:2:2 -> horizontal averaging
    rule r_422_even (rg_mode == YCBCR_422 && !col_odd);
        let px = f_in.first; f_in.deq;
        rg_prev <= px;
        advance_col();
    endrule
    
    //elements from odd columns are sum-reduced with the previous element
    rule r_422_odd (rg_mode == YCBCR_422 && col_odd);
        let px = f_in.first; f_in.deq;
        f_out.enq(avg2(rg_prev, px));
        advance_col();
    endrule

    
    //4:2:0 -> horizontal and vertical averaging
    //Line buffer: stores horizontal averages of even rows (max_img_width/2 entries)

    if (use_bram) begin
        BRAM_Configure bram_cfg = defaultValue;
        bram_cfg.memorySize = valueOf(TDiv#(max_img_width, 2));
        bram_cfg.latency = 1;
        BRAM1Port#(Bit#(line_addr_w), UInt#(8)) line_bram <- mkBRAM1Server(bram_cfg);

        //even column: store pixel; on odd rows prefetch the line buffer via BRAM
        rule r_420_even_col (rg_mode == YCBCR_420 && !col_odd);
            let px = f_in.first; f_in.deq;
            rg_prev <= px;
            if (rg_row_odd)
                line_bram.portA.request.put(BRAMRequest {
                    write: False, responseOnWrite: False,
                    address: pair_idx, datain: ?
                });
            advance_col();
        endrule

        //odd column, even row: write horizontal avg into BRAM
        rule r_420_odd_even_row (rg_mode == YCBCR_420 && col_odd && !rg_row_odd);
            let px = f_in.first; f_in.deq;
            let h_avg = avg2(rg_prev, px);
            line_bram.portA.request.put(BRAMRequest {
                write: True, responseOnWrite: False,
                address: pair_idx, datain: h_avg
            });
            advance_col();
        endrule

        //odd column, odd row: consume prefetched BRAM response, average vertically, emit
        rule r_420_odd_odd_row (rg_mode == YCBCR_420 && col_odd && rg_row_odd);
            let px = f_in.first; f_in.deq;
            let h_avg = avg2(rg_prev, px);
            let prev_avg <- line_bram.portA.response.get();
            let v_avg = avg2(h_avg, prev_avg);
            f_out.enq(v_avg);
            advance_col();
        endrule

    end else begin
        // --- RegFile path with combinational read, uses LUTRAM ---
        RegFile#(Bit#(line_addr_w), UInt#(8)) line_buf <- mkRegFileFull;

        rule r_420_even_col (rg_mode == YCBCR_420 && !col_odd);
            let px = f_in.first; f_in.deq;
            rg_prev <= px;
            advance_col();
        endrule

        rule r_420_odd_even_row (rg_mode == YCBCR_420 && col_odd && !rg_row_odd);
            let px = f_in.first; f_in.deq;
            let h_avg = avg2(rg_prev, px);
            line_buf.upd(pair_idx, h_avg);
            advance_col();
        endrule

        rule r_420_odd_odd_row (rg_mode == YCBCR_420 && col_odd && rg_row_odd);
            let px = f_in.first; f_in.deq;
            let h_avg = avg2(rg_prev, px);
            let v_avg = avg2(h_avg, line_buf.sub(pair_idx));
            f_out.enq(v_avg);
            advance_col();
        endrule
    end

    method Action configure(SubsamplingMode_t mode, Bit#(13) img_width);
        rg_mode      <= mode;
        rg_img_width <= img_width;
        rg_col       <= 0;
        rg_row_odd   <= False;
    endmethod

    method Action rewind();
        rg_col     <= 0;
        rg_row_odd <= False;
    endmethod

    interface pixel_in  = toPut(f_in);
    interface pixel_out = toGet(f_out);

endmodule

endpackage