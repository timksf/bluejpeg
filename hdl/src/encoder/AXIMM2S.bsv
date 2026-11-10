package AXIMM2S;

import GetPut :: *;
import ClientServer :: *;
import FIFO :: *;
import FIFOF :: *;
import BRAMFIFO :: *;
import SpecialFIFOs :: *;
import Vector :: *;
import BUtils :: *;
import Assert :: *;
import BlueAXI :: *;

import EncoderUtil :: *;

Integer cfg_cmd_control_offs   = 'h00;
Integer cfg_cmd_cause_offs     = 'h04;
Integer cfg_start_addr_lo_offs = 'h10;
Integer cfg_start_addr_hi_offs = 'h14;
Integer cfg_tx_bytes_lo_offs   = 'h18;
Integer cfg_tx_bytes_hi_offs   = 'h1C;
Integer cfg_tx_counter_lo_offs = 'h20;
Integer cfg_tx_counter_hi_offs = 'h24;

//bit offsets in control register
Integer cfg_start_bit_offs  = 0;
Integer cfg_finish_bit_offs = 1;
Integer cfg_error_bit_offs  = 2;

typedef enum {
    ReqBytesUnaligned //the requested number of bytes is not aligned with the bytes per stream packet
} AXIMM2SErrorCause deriving(Bits, Eq, FShow);

interface AXIMM2S_ifc#(numeric type aw, numeric type dw, numeric type sdw);
    //MM read master
    (*prefix="RD_DATA"*)
    interface AXI4_Master_Rd_Fab#(aw, dw, 0, 0) fab_mm_rd;

    //stream output
    (*prefix="M_AXIS"*)
    interface AXI4_Stream_Wr_Fab#(sdw, 0) fab_s_wr;

    //config interface
    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) fab_config_rd;
    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) fab_config_wr;
endinterface

//internal interface to the configuration registers
interface AXIMM2SCfg_ifc;

    method Action finish(); //signal finished processing
    method Action error(AXIMM2SErrorCause c);

    interface ReadOnly#(Bit#(32)) ctrl; //use only for debugging
    interface ReadOnly#(Bool) start;
    interface ReadOnly#(Bit#(64)) start_addr;
    interface ReadOnly#(Bit#(64)) tx_bytes;
    interface WriteOnly#(Bit#(64)) tx_counter;

endinterface

module [ConfigCtx#(32, 32)] aximm2s_config(AXIMM2SCfg_ifc);

    Reg#(Bit#(32))          rg_cmd_control     <- mkReg(0);
    Reg#(AXIMM2SErrorCause) rg_cmd_error_cause <- mkRegU;

    Reg#(Bit#(32)) rg_start_addr_lo <- mkRegU;
    Reg#(Bit#(32)) rg_start_addr_hi <- mkRegU;

    Reg#(Bit#(32)) rg_tx_bytes_lo <- mkRegU;
    Reg#(Bit#(32)) rg_tx_bytes_hi <- mkRegU;

    Reg#(Bit#(32)) rg_tx_counter_lo <- mkRegU;
    Reg#(Bit#(32)) rg_tx_counter_hi <- mkRegU;

    //add registers to AXI interface
    addReg(cfg_cmd_control_offs, rg_cmd_control);

    addRegRO(cfg_cmd_cause_offs, rg_cmd_error_cause);

    addReg(cfg_start_addr_lo_offs, rg_start_addr_lo);
    addReg(cfg_start_addr_hi_offs, rg_start_addr_hi);

    addReg(cfg_tx_bytes_lo_offs, rg_tx_bytes_lo);
    addReg(cfg_tx_bytes_hi_offs, rg_tx_bytes_hi);

    addRegRO(cfg_tx_counter_lo_offs, rg_tx_counter_lo);
    addRegRO(cfg_tx_counter_hi_offs, rg_tx_counter_hi);

    method finish = action
        let p = rg_cmd_control;
        p[cfg_start_bit_offs] = 0; //ideally this bit would be cleared on read
        p[cfg_finish_bit_offs] = 1;
        rg_cmd_control <= p;
    endaction;

    method error(c) = action
        let p = rg_cmd_control;
        p[cfg_error_bit_offs] = 1;
        rg_cmd_control <= p;
        rg_cmd_error_cause <= c;
    endaction;

    interface WriteOnly tx_counter;
        method Action _write(Bit#(64) v);
            rg_tx_counter_lo <= v[31:0];
            rg_tx_counter_hi <= v[63:32];
        endmethod
    endinterface

    interface ReadOnly start;
        method _read = unpack(rg_cmd_control[cfg_start_bit_offs]);
    endinterface

    interface ReadOnly start_addr;
        method _read = {rg_start_addr_hi, rg_start_addr_lo};
    endinterface

    interface ReadOnly tx_bytes;
        method _read = {rg_tx_bytes_hi, rg_tx_bytes_lo};
    endinterface

    interface ctrl = regToReadOnly(rg_cmd_control);

endmodule

/*
    Each beat coming in on the MM side corresponds to exactly one packet on the S side.
    So if the MM bus is wider than the stream bus, the incoming beats read on the MM side are narrowed down
    before being put out on the stream bus!
*/
module [Module] mkAXIMM2S#(Integer burst_length, Integer max_outstanding)(AXIMM2S_ifc#(aw, dw, sdw))
    provisos(
        NumAlias#(4096, barrier),
        Log#(barrier, barrier_bits),
        Min#(dw, sdw, datawidth), //actually used width on MM bus is dw iff dw == sdw, otherwise narrow bursts
        Add#(sdw, 0, datawidth), //sdw == datawidth, as stream width is used in internal buffer
        Mul#(data_bytes, 8, datawidth), //bytes on the MM data line
        Div#(barrier, data_bytes, burst_length_max), //max. #bytes per burst based on the 4096 barrier
        Max#(aw, 64, 64), //aw <= 64
        Mul#(8, bytes_per_beat, dw) //bytes_per_beat = dw/8
        //Add#(12, a__, aw) //aw >= 12
        //Log#(bytes_per_beat)
    );

    staticAssert(is_power_of_2(burst_length) && burst_length <= 256, "Burst length is required to be a power of 2 leq 256");

    Integer burst_size      = valueof(bytes_per_beat);   //bytes per beat in a burst
    Integer bytes_per_burst = burst_size * burst_length; //bytes per full burst (AxSIZE**2 * AxLEN)

    staticAssert(burst_length <= valueof(burst_length_max),
        "Burst length " + integerToString(burst_length) + " exceeds 4096 bytes with " + integerToString(burst_length*burst_size));

    //AXIMM ifc
    AXI4_Master_Rd#(aw, dw, 0, 0)             i_aximm_rd <- mkAXI4_Master_Rd(1, 1, False);
    //AXIS ifc
    AXI4_Stream_Wr#(sdw, 0)                   i_axis_wr  <- mkAXI4_Stream_Wr(1);
    //AXIL config
    IntExtConfig_ifc#(32, 32, AXIMM2SCfg_ifc) config_    <- axi4LiteConfigFromContext(aximm2s_config);

    //buffer between MM receive and stream output, tagged with last flag
    //Tuple2: (data, last)
    FIFO#(Tuple2#(Bit#(datawidth), Bool)) f_buffer           <- mkFIFO;
    Reg#(Bool)                            rg_running         <- mkReg(False);
    Reg#(Bit#(aw))                        rg_current_addr    <- mkRegU;
    Reg#(Bit#(aw))                        rg_final_addr      <- mkRegU;
    Reg#(Bit#(64))                        rg_bytes_remaining <- mkRegU;
    Reg#(Bit#(64))                        rg_bytes_sent      <- mkReg(0);
    //place token in this FIFO for each request, remove token when last data arrived
    FIFO#(Bit#(0))                        f_outstanding      <- mkSizedFIFO(max_outstanding);

    function Bit#(TAdd#(1, barrier_bits)) bytes_til_barrier(Bit#(w) addr);
        Bit#(TAdd#(1, barrier_bits)) e_addr  = cExtend(addr);
        Bit#(TAdd#(1, barrier_bits)) barrier = fromInteger(valueof(barrier));
        return barrier - addr[valueof(barrier_bits):0];
    endfunction

    rule r_init (config_.device_ifc.start() && !rg_running);
        let start_addr = config_.device_ifc.start_addr()[valueof(aw)-1:0];
        rg_current_addr <= start_addr;
        let bytes_to_send = config_.device_ifc.tx_bytes();
        rg_bytes_remaining <= bytes_to_send;
        rg_bytes_sent <= 0;
        //error if bytes to handle not divisible by bytes per stream packet
        if(bytes_to_send % fromInteger(valueof(data_bytes)) != 0) begin
            config_.device_ifc.error(ReqBytesUnaligned);
            rg_running <= False;
        end else begin
            rg_running <= True;
        end
        rg_final_addr <= start_addr + (bytes_to_send[valueof(aw)-1:0] / fromInteger(valueof(data_bytes))) << fromInteger(valueof(TLog#(bytes_per_beat)));
    endrule

    rule r_issue_req (rg_running && rg_current_addr != rg_final_addr);
        //this should satisfy the max. outstanding requests supported by connected slaves
        //also have to take care to not cross 4k barriers with any request
        AXI4_Read_Rq#(aw, 0, 0) request = defaultValue;
        request.addr = rg_current_addr;
        request.burst_size = bitsToBurstSize(valueof(dw));
        request.burst_type = INCR;

        let legal_bytes   = bytes_til_barrier(rg_current_addr);
        let bytes_to_send = legal_bytes != 0 ? min(extend(legal_bytes), rg_bytes_remaining) : rg_bytes_remaining;
        if(fromInteger(bytes_per_burst) > bytes_to_send) begin
            //cannot issue a full burst
            //calculate max. possible burst length before crossing barrier
            //note: we only receive "data_bytes" bytes per transfer because of narrowing!
            let max_burst_len = bytes_to_send / fromInteger(valueof(data_bytes));
            request.burst_length = truncate(unpack(max_burst_len)) - 1;
        end else begin
            request.burst_length = fromInteger(burst_length) - 1;
        end
        f_outstanding.enq(?);
        UInt#(aw) bytes_this_burst = cExtend(request.burst_length + 1) << fromInteger(valueof(TLog#(bytes_per_beat)));
        let next_addr = rg_current_addr + pack(bytes_this_burst);
        rg_current_addr <= next_addr;
        i_aximm_rd.request.put(request);
    endrule

    rule r_rec_data (rg_running);
        let rsp <- i_aximm_rd.response.get();
        if(rsp.resp == OKAY) begin
            //narrowing happens here, if sdw < dw
            Bit#(datawidth) d = rsp.data[valueof(datawidth)-1:0];
            let remaining = rg_bytes_remaining - fromInteger(valueof(TDiv#(datawidth, 8)));
            rg_bytes_remaining <= remaining;
            f_buffer.enq(tuple2(d, remaining == 0));
        end else begin
            //non-OKAY response: signal error and abort
            config_.device_ifc.error(ReqBytesUnaligned); //TODO: add separate error cause for AXI resp error
            rg_running <= False;
        end
        if(rsp.last)
            f_outstanding.deq;
    endrule

    rule r_stream_out (rg_running);
        match {.d, .last} = f_buffer.first; f_buffer.deq;
        i_axis_wr.pkg.put(AXI4_Stream_Pkg {
            data: d,
            user: ?,
            keep: unpack(-1), //keep all, as always datawidth == sdw
            dest: ?,
            id: 0,
            last: last
        });
        rg_bytes_sent <= rg_bytes_sent + fromInteger(valueof(TDiv#(datawidth, 8)));
        config_.device_ifc.tx_counter._write(rg_bytes_sent + fromInteger(valueof(TDiv#(datawidth, 8))));
        if(last) begin //indicate finished transfers in config registers
            rg_running <= False;
            config_.device_ifc.finish();
        end
    endrule

    //MM
    interface fab_mm_rd = i_aximm_rd.fab;
    //s
    interface fab_s_wr = i_axis_wr.fab;
    //config
    interface fab_config_rd = config_.bus_ifc.s_rd;
    interface fab_config_wr = config_.bus_ifc.s_wr;

endmodule

endpackage
