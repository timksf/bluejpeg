package TestQuantize;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import BuildVector :: *;
import ClientServer :: *;

import BDPI :: *;
import Util :: *;
import Quantize :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;

//fractional bits of the AAN multipliers, shared by the DUT and the reference
typedef 8 QuantScale;

module [Module] mkTestQuantize(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    Integer n_tests = 10;

    NumProxy_t#(QuantScale) f_scale = ?;
    Quant_ifc#(12)          dut     <- mkQuantize(f_scale, False, True, False);

    Reg#(Bit#(32)) rg_counter <- mkReg(0);
    Reg#(Bit#(32)) rg_errors  <- mkReg(0);

    Reg#(Bit#(7)) rg_in_idx  <- mkReg(0);
    Reg#(Bit#(7)) rg_out_idx <- mkReg(0);

    Reg#(DU_t#(Int#(12), 8, 8)) rg_in_mcu  <- mkRegU;
    Reg#(DU_t#(Int#(12), 8, 8)) rg_ref_mcu <- mkRegU;
    Reg#(DU_t#(Int#(12), 8, 8)) rg_res_mcu <- mkRegU;

    Stmt test_seq = seq
        dut.rewind();

        while(rg_counter < fromInteger(n_tests)) seq
            dut.du_mode.put(Luma); //put mode once per DU
            action
                Vector#(8, Vector#(8, Int#(12))) in_block = newVector;
                for(Integer i = 0; i < 8; i = i + 1) begin
                    for(Integer j = 0; j < 8; j = j + 1) begin
                        let pix <- rand_pix();
                        Int#(16) pix_i16 = unpack(zeroExtend(pack(pix)));
                        //expand magnitude back up to represent somewhat realistic DCT coefficients
                        Int#(12) val     = truncate(pix_i16 - 128) * 8;
                        in_block[i][j] = val;
                    end
                end
                rg_in_mcu <= DU_t { block: in_block };
            endaction

            par
                seq
                    rg_in_idx <= 0;
                    while(rg_in_idx < 64) action
                        Bit#(3) row = truncate(rg_in_idx >> 3);
                        Bit#(3) col = truncate(rg_in_idx);
                        dut.data.request.put(rg_in_mcu.block[row][col]);
                        rg_in_idx <= rg_in_idx + 1;
                    endaction
                endseq

                seq
                    rg_out_idx <= 0;
                    while(rg_out_idx < 64) action
                        let hw_res <- dut.data.response.get();
                        Bit#(3) row = truncate(rg_out_idx >> 3);
                        Bit#(3) col = truncate(rg_out_idx);
                        let val = rg_in_mcu.block[row][col];
//
                        let expected_wide <- quant_ref_i16(signExtend(val), zeroExtend(rg_out_idx), True, True, fromInteger(valueOf(QuantScale)));
                        Int#(12) expected = truncate(expected_wide);

                        let bs = rg_res_mcu;
                        bs.block[row][col] = hw_res;
                        rg_res_mcu <= bs;

                        let br = rg_ref_mcu;
                        br.block[row][col] = expected;
                        rg_ref_mcu <= br;

                        rg_out_idx <= rg_out_idx + 1;
                    endaction
                endseq
            endpar

            action
                print_du(rg_in_mcu, "DU_t input", CYAN);
                print_du(rg_ref_mcu, "DU_t expected", GREEN);
                print_du(rg_res_mcu, "DU_t hardware", GREEN);

                function Int#(12) calc_diff(Integer idx);
                    Integer  r       = idx / 8;
                    Integer  c       = idx % 8;
                    Int#(12) hw_val  = rg_res_mcu.block[r][c];
                    Int#(12) ref_val = rg_ref_mcu.block[r][c];
                    return (hw_val > ref_val) ? hw_val - ref_val : ref_val - hw_val;
                endfunction
                Vector#(64, Int#(12)) diffs = genWith(calc_diff);
                function Int#(12) max_func(Int#(12) a, Int#(12) b) = (a > b) ? a : b;
                Int#(12) max_diff = fold(max_func, diffs);

                //the hardware is bit-exact to the reference, so any difference is an error
                if(max_diff > 0) begin
                    print_fmt($format("Test %0d, max error: %0d", rg_counter, max_diff), RED);
                    rg_errors <= rg_errors + 1;
                end

                rg_counter <= rg_counter + 1;
            endaction
        endseq

        if(rg_errors == 0) print_s("PASSED", GREEN);
        else print_fmt($format("FAILED with %d errors", rg_errors), RED);
    endseq;

    FSM i_test_fsm <- mkFSM(test_seq);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

endpackage
