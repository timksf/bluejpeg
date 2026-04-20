package AXI4LiteTestHelper;

import StmtFSM :: *;
import BlueAXI :: *;

function Stmt axil_read(AXI4_Lite_Master_Rd#(a, d) m, Bit#(a) addr, Reg#(Bit#(d)) rg_out);
    return seq
        axi4_lite_read(m, addr);
        action
            let rsp <- axi4_lite_read_response(m);
            rg_out <= rsp;
        endaction
    endseq;
endfunction

endpackage
