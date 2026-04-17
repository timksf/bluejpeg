package DUDebug;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import Types :: *;
import Util :: *;
import PrintUtil :: *;

interface DUDebug_ifc#(type t, numeric type w, numeric type h);

    interface Put#(t) pix_i;
    interface Get#(t) pix_o;

endinterface

module mkDUDebug#(String tag)(DUDebug_ifc#(t, w, h)) provisos(Bits#(t, __st), FShow#(t));

    FIFO#(t) f_in   <- mkPipelineFIFO;
    FIFO#(t) f_out  <- mkPipelineFIFO;

    // ---- accumulation state (flat to avoid 2D dynamic indexing into Vector#(1,...)) ----
    Reg#(Vector#(TMul#(w,h), t)) rg_block <- mkRegU;
    Reg#(Bit#(TAdd#(TLog#(TMul#(w, h)), 1)))  rg_cnt   <- mkReg(0);

    Reg#(Bool) rg_ready <- mkReg(False);

    rule raccumulate (!rg_ready);
        let pix = f_in.first; f_in.deq;
        Vector#(TMul#(w,h), t) blk = rg_block;
        blk[rg_cnt] = pix;
        rg_block <= blk;
        if (rg_cnt == fromInteger(valueof(TMul#(w,h)))-1) begin
            Vector#(h, Vector#(w, t)) blk2d = ?;
            for (Integer y = 0; y < valueof(h); y = y + 1)
                for (Integer x = 0; x < valueof(w); x = x + 1)
                    blk2d[y][x] = blk[y * valueof(w) + x];
            print_du(DU_t { block: blk2d }, tag, YELLOW);
            rg_ready <= True;
        end else
            rg_cnt <= rg_cnt + 1;
    endrule

    rule rdrain (rg_ready);
        f_out.enq(rg_block[fromInteger(valueof(TMul#(w,h)))-rg_cnt-1]);
        if (rg_cnt == 0) begin
            rg_ready <= False;
        end else
            rg_cnt <= rg_cnt - 1;
    endrule

    interface pix_i = toPut(f_in);
    interface pix_o = toGet(f_out);

endmodule

endpackage
