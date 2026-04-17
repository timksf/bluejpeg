package TestDCT1D;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import BuildVector :: *;
import ClientServer :: *;

import BDPI :: *;
import Util :: *;
import DCT1D :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;

function ActionValue#(Bit#(64)) dct_1d_i8_ref(Bit#(64) in, Bool scale) = actionvalue
    Bit#(65) in_padded = {1'b0, in};
    let v <- dct_1d_i8_ref_raw(in_padded, scale);
    return v[63:0];
endactionvalue;

module [Module] mkTestDCT1D(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    NumProxy#(8) f_scale = ?;
    DCT1D_ifc#(12) dut <- mkDCT1D(f_scale, True);

    Reg#(Bit#(32)) rg_counter <- mkReg(0);
    Reg#(Bit#(32)) rg_errors <- mkReg(0);

    FIFO#(Vector#(8, Int#(12))) f_tv <- mkFIFO;

    Stmt test_seq = seq
        while(rg_counter < 5) seq
            action
                Vector#(8, Int#(12)) row = newVector;

                for(Integer i=0; i<8; i=i+1) begin
                    let pix <- rand_pix();
                    Int#(16) pix_i16 = unpack(zeroExtend(pack(pix)));
                    row[i] = truncate(pix_i16 - 128);
                end

                print_fmt($format("ROW ") + fshow(row), CYAN);
                dut.data.request.put(row);
                f_tv.enq(row);

            endaction
            action
                let input_row = f_tv.first; f_tv.deq;
                Vector#(8, Int#(16)) ext_row = map(signExtend, input_row);
                let ref_out_packed <- dct_1d_i16_ref(pack(ext_row), True);
                Vector#(8, Int#(16)) ref_wide = unpack(ref_out_packed);
                Vector#(8, Int#(12)) ref_out = map(truncate, ref_wide);
                
                let res <- dut.data.response.get();

                print_fmt($format("REF ") + fshow(ref_out), GREEN);
                print_fmt($format("RES ") + fshow(res), GREEN);

                rg_counter <= rg_counter + 1;
            endaction
        endseq
    endseq;

    FSM testFSM <- mkFSM(test_seq);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod

endmodule

endpackage
