package AXIStreamConverters;

import AXI4_Stream :: *;
import Clocks :: *;

interface AXIStreamUpConverter#(numeric type inwidth, numeric type outwidth, numeric type userwidth);
    (* prefix="S_AXIS" *) interface AXI4_Stream_Rd_Fab#(inwidth, userwidth) s_axis;
    (* prefix="M_AXIS" *) interface AXI4_Stream_Wr_Fab#(outwidth, userwidth) m_axis;
endinterface

function Bit#(outwidth) insert_axis_chunk(Bit#(outwidth) word, UInt#(lanewidth) lane, Bit#(inwidth) data)
    provisos(
        Add#(a__, inwidth, outwidth),
        Add#(b__, lanewidth, TLog#(TAdd#(outwidth, 1)))
    );
    UInt#(TLog#(TAdd#(outwidth, 1))) shift_bits = zeroExtend(lane) * fromInteger(valueOf(inwidth));
    Bit#(inwidth)                    chunk_mask = '1;
    Bit#(outwidth)                   mask       = zeroExtend(chunk_mask) << pack(shift_bits);
    Bit#(outwidth)                   chunk      = zeroExtend(data) << pack(shift_bits);
    return (word & ~mask) | chunk;
endfunction

module mkAXIStreamUpConverter(AXIStreamUpConverter#(inwidth, outwidth, userwidth))
    provisos(
        Add#(a__, inwidth, outwidth),
        Div#(inwidth, 8, inbytes),
        Mul#(inwidth, ratio, outwidth),
        Add#(c__, TLog#(TAdd#(ratio, 1)), TLog#(TAdd#(outwidth, 1)))
    );

    let isRst <- isResetAsserted();

    Wire#(Bool)                           tvalidIn  <- mkBypassWire();
    Wire#(Bit#(inwidth))                  dataIn    <- mkBypassWire();
    Wire#(Bool)                           lastIn    <- mkBypassWire();
    Wire#(Bool)                           treadyIn  <- mkBypassWire();

    Reg#(UInt#(TLog#(TAdd#(ratio, 1))))   rg_lane        <- mkReg(0);
    Reg#(Bit#(outwidth))                  rg_word        <- mkReg(0);

    Integer chunks_per_output = valueOf(ratio);

    Bit#(outwidth) next_word          = insert_axis_chunk(rg_word, rg_lane, dataIn);
    Bool           output_complete    = rg_lane == fromInteger(chunks_per_output - 1);
    Bool           partial_frame_last = lastIn && !output_complete;
    Bool           input_ready        = !isRst && (!output_complete || treadyIn);
    Bool           input_fire         = input_ready && tvalidIn;

    rule rconsume if(input_fire);
        if(partial_frame_last) begin
            rg_word <= 0;
            rg_lane <= 0;
        end else if(output_complete) begin
            rg_word <= 0;
            rg_lane <= 0;
        end else begin
            rg_word <= next_word;
            rg_lane <= rg_lane + 1;
        end
    endrule

    interface AXI4_Stream_Rd_Fab s_axis;
        method Bool tready = input_ready;
        method Action ptvalid(Bool tvalid);
            tvalidIn <= tvalid;
        endmethod
        method Action ptdata(Bit#(inwidth) data);
            dataIn <= data;
        endmethod
        method Action ptuser(Bit#(userwidth) user);
        endmethod
        method Action ptkeep(Bit#(TDiv#(inwidth, 8)) keep);
        endmethod
        method Action ptDest(Bit#(4) dest);
        endmethod
        method Action ptid(Bit#(8) id);
        endmethod
        method Action ptlast(Bool last);
            lastIn <= last;
        endmethod
    endinterface

    interface AXI4_Stream_Wr_Fab m_axis;
        method Bool tvalid = !isRst && tvalidIn && output_complete;
        method Action ptready(Bool tr);
            treadyIn <= tr;
        endmethod
        method Bit#(outwidth) tdata = next_word;
        method Bool tlast = lastIn;
        method Bit#(userwidth) tuser = 0;
        method Bit#(TDiv#(outwidth, 8)) tkeep = '1;
        method Bit#(4) tDest = 0;
        method Bit#(8) tid = 0;
    endinterface
endmodule

endpackage
