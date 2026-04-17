package TestZigZag;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import BuildVector :: *;
import ClientServer :: *;

import BDPI :: *;
import Util :: *;
import ZigZag :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;

module [Module] mkTestZigZag(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    Integer n_tests = 100;

    //
    Bool verbose        = False;
    Bool is_transposed  = False;

    Zigzag_ifc#(16) dut <- mkZigZag(False, is_transposed);

    Reg#(Bit#(32)) rg_counter <- mkReg(0);
    Reg#(Bit#(32)) rg_errors <- mkReg(0);
    
    Reg#(Bit#(7)) rg_in_idx <- mkReg(0);
    Reg#(Bit#(7)) rg_out_idx <- mkReg(0);

    Reg#(DU_t#(Int#(16), 8, 8)) rg_in_mcu <- mkRegU;
    Reg#(DU_t#(Int#(16), 8, 8)) rg_ref_mcu <- mkRegU;
    Reg#(DU_t#(Int#(16), 8, 8)) rg_res_mcu <- mkRegU;

    Stmt test_seq = seq
        while(rg_counter < fromInteger(n_tests)) seq
            action
                Vector#(8, Vector#(8, Int#(16))) in_block = newVector;
                for (Integer i = 0; i < 8; i = i + 1) begin
                    for (Integer j = 0; j < 8; j = j + 1) begin
                        let pix <- rand_pix();
                        Int#(16) val = unpack(zeroExtend(pack(pix))) - 128;
                        in_block[i][j] = val;
                    end
                end
                rg_in_mcu <= DU_t { block: in_block };
            endaction

            //compute reference
            action
                let bs = rg_in_mcu;
                Bit#(1024) packed_in = pack(bs);
                let packed_out <- zigzag_ref_i16(packed_in, is_transposed);
                DU_t#(Int#(16), 8, 8) ref_mcu = unpack(packed_out);
                rg_ref_mcu <= ref_mcu;
            endaction

            par
                seq
                    rg_in_idx <= 0;
                    while (rg_in_idx < 64) action
                        Bit#(3) row = truncate(rg_in_idx >> 3);
                        Bit#(3) col = truncate(rg_in_idx);
                        dut.data.request.put(rg_in_mcu.block[row][col]);
                        rg_in_idx <= rg_in_idx + 1;
                    endaction
                endseq
                
                seq
                    rg_out_idx <= 0;
                    while (rg_out_idx < 64) action
                        let hw_res <- dut.data.response.get();
                        Bit#(3) row = truncate(rg_out_idx >> 3);
                        Bit#(3) col = truncate(rg_out_idx);
                        
                        let bs = rg_res_mcu;
                        bs.block[row][col] = hw_res;
                        rg_res_mcu <= bs;
                        
                        rg_out_idx <= rg_out_idx + 1;
                    endaction
                endseq
            endpar
            
            action
                function Int#(16) calc_diff(Integer idx);
                    Integer r = idx / 8;
                    Integer c = idx % 8;
                    Int#(16) hw_val = rg_res_mcu.block[r][c];
                    Int#(16) ref_val = rg_ref_mcu.block[r][c];
                    return (hw_val > ref_val) ? hw_val - ref_val : ref_val - hw_val;
                endfunction
                Vector#(64, Int#(16)) diffs = genWith(calc_diff);
                function Int#(16) max_func(Int#(16) a, Int#(16) b) = (a > b) ? a : b;
                Int#(16) max_diff = fold(max_func, diffs);

                if (verbose || max_diff > 0) begin
                    print_du(rg_in_mcu, "DU_t input", CYAN);
                    print_du(rg_ref_mcu, "DU_t expected", GREEN);
                    print_du(rg_res_mcu, "DU_t hardware", GREEN);
                end

                if (max_diff > 0) begin
                    print_fmt($format("Test %0d, max error: %0d", rg_counter, max_diff), RED);
                    rg_errors <= rg_errors + 1;
                end
                
                rg_counter <= rg_counter + 1;
            endaction
        endseq
        
        if (rg_errors == 0) print_s("PASSED", GREEN);
        else print_fmt($format("FAILED with %d errors", rg_errors), RED);
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