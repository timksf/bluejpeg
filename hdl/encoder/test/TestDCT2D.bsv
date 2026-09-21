package TestDCT2D;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import Connectable :: *;
import BuildVector :: *;
import ClientServer :: *;

import BDPI :: *;
import Util :: *;
import DCT2D :: *;
import DCT2D_Optimized :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;

(* synthesize *)
module [Module] mkTestDCT2D(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t1 <- test;
    let t2 <- testOpt;

    Stmt s = seq
        print_s("Testing mkDCT2D...", BLUE);
        t1.go();
        while(!t1.done()) action endaction
        print_s("Testing mkDCT2D_Opt_rigid...", BLUE);
        t2.go();
        while(!t2.done()) action endaction
    endseq;

    FSM testFSM <- mkFSM(s);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod

endmodule

module [Module] test(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    NumProxy#(12) dct_scale = ?;
    DCT2D_ifc#(12) dut <- mkDCT2D(dct_scale, False);
    
    Reg#(Bit#(32)) rg_counter <- mkReg(0);
    Reg#(Bit#(32)) rg_errors <- mkReg(0);

    //flattened MCUs for BDPI
    Reg#(Bit#(1024)) input_flat <- mkRegU;
    Reg#(Bit#(1024)) output_ref_flat <- mkRegU;
    Reg#(DU_t#(Int#(12), 8, 8)) rg_mcu_in <- mkRegU;

    Stmt test_seq = seq
        dut.rewind();
        while(rg_counter < 10) seq
            dut.rewind(); //TODO automatic rewind
            action
                Vector#(8, Vector#(8, Int#(12))) block_2d = newVector;

                for(Integer i=0; i<8; i=i+1)
                    for(Integer j=0; j<8; j=j+1) begin
                        let pix <- rand_pix();
                        Int#(16) pix_i16 = unpack(zeroExtend(pack(pix)));
                        block_2d[i][j] = truncate(pix_i16 - 128); //random pixel then mean shift
                    end
                
                DU_t#(Int#(12), 8, 8) mcu = DU_t { block: block_2d };
                rg_mcu_in <= mcu;
                dut.data.request.put(mcu);
                
                //store for reference calc
                Vector#(8, Vector#(8, Int#(16))) ref_input = map(map(signExtend), block_2d);
                input_flat <= pack(ref_input);
            endaction
            
            //calculate reference and compare
            action
                let ref_out_packed <- dct_2d_i16_ref(input_flat, False);
                Vector#(8, Vector#(8, Int#(16))) ref_out = unpack(ref_out_packed);
                let res <- dut.data.response.get();
                let res_tp = transpose_mcu(res); //replaces the output transpose buffer
                let hw_block = res_tp.block;
                
                DU_t#(Int#(12), 8, 8) ref_ = DU_t { block: map(map(truncate), ref_out) };

                Bool res_match = True;

                function Int#(12) calc_diff(Integer idx);
                    Integer r = idx / 8;
                    Integer c = idx % 8;
                    Int#(12) hw_val = hw_block[r][c];
                    Int#(12) ref_val = ref_.block[r][c];
                    return (hw_val > ref_val) ? hw_val - ref_val : ref_val - hw_val;
                endfunction
                Vector#(64, Int#(12)) diffs = genWith(calc_diff);
                function Int#(12) max_func(Int#(12) a, Int#(12) b) = (a > b) ? a : b;
                Int#(12) max_diff = fold(max_func, diffs);

                print_mod_pre_color_t_f($format("Test %0d, max error: %0d", rg_counter, max_diff), WHITE);
                
                if (max_diff > 20) begin
                    print_du(rg_mcu_in, "DU_t input", BLUE);
                    print_du(ref_, "DU_t reference output", CYAN);
                    print_du(res_tp, "DU_t DUT output", YELLOW);
                    print_fmt($format("Error>20 at iteration %d", rg_counter), RED);
                    rg_errors <= rg_errors + 1;
                end
            endaction
            rg_counter <= rg_counter + 1;
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

module [Module] testOpt(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    NumProxy#(12) dct_scale = ?;
    DCT2DOptRigid_ifc#(8) dut <- mkDCT2D_Opt_rigid(dct_scale, False, True, False, False);
    
    Reg#(Bit#(32)) rg_counter <- mkReg(0);
    Reg#(Bit#(32)) rg_errors <- mkReg(0);

    //flattened MCUs for BDPI
    Reg#(Bit#(1024)) input_flat <- mkRegU;

    Reg#(Bit#(4)) rg_count_in  <- mkReg(0);
    Reg#(Bit#(4)) rg_count_out <- mkReg(0);
    
    Reg#(DU_t#(Int#(8), 8, 8))  rg_mcu_in  <- mkRegU;
    Reg#(DU_t#(Int#(15), 8, 8)) rg_mcu_out <- mkRegU;

    Stmt test_seq = seq
        dut.rewind();
        while(rg_counter < 10) seq
            dut.rewind(); //TODO automatic rewind
            action
                Vector#(8, Vector#(8, Int#(8))) block_2d = newVector;

                for(Integer i=0; i<8; i=i+1)
                    for(Integer j=0; j<8; j=j+1) begin
                        let pix <- rand_pix();
                        Int#(16) pix_i16 = unpack(zeroExtend(pack(pix)));
                        block_2d[i][j] = truncate(pix_i16 - 128); //random pixel then mean shift
                    end
                
                DU_t#(Int#(8), 8, 8) mcu = DU_t { block: block_2d };
                rg_mcu_in <= mcu;
                
                //store for reference calc
                Vector#(8, Vector#(8, Int#(16))) ref_input = map(map(signExtend), block_2d);
                input_flat <= pack(ref_input);
            endaction
            
            rg_count_in <= 0;
            rg_count_out <= 0;
            
            par
                while(rg_count_in < 8) action
                    dut.data.request.put(rg_mcu_in.block[rg_count_in]);
                    rg_count_in <= rg_count_in + 1;
                endaction
                while(rg_count_out < 8) action
                    let res <- dut.data.response.get();
                    let block = rg_mcu_out.block;
                    block[rg_count_out] = res;
                    rg_mcu_out <= DU_t { block: block };
                    rg_count_out <= rg_count_out + 1;
                endaction
            endpar
            
            //calculate reference and compare
            action
                let ref_out_packed <- dct_2d_i16_ref(input_flat, False);
                Vector#(8, Vector#(8, Int#(16))) ref_out = unpack(ref_out_packed);
                
                let res_tp = transpose_mcu(rg_mcu_out); 
                let hw_block = res_tp.block;
                
                DU_t#(Int#(16), 8, 8) ref_ = DU_t { block: ref_out };

                Bool res_match = True;

                function Int#(16) calc_diff(Integer idx);
                    Integer r = idx / 8;
                    Integer c = idx % 8;
                    Int#(16) hw_val = signExtend(hw_block[r][c]);
                    Int#(16) ref_val = ref_.block[r][c];
                    return (hw_val > ref_val) ? hw_val - ref_val : ref_val - hw_val;
                endfunction
                Vector#(64, Int#(16)) diffs = genWith(calc_diff);
                function Int#(16) max_func(Int#(16) a, Int#(16) b) = (a > b) ? a : b;
                Int#(16) max_diff = fold(max_func, diffs);

                print_mod_pre_color_t_f($format("Test %0d, max error: %0d", rg_counter, max_diff), WHITE);
                
                if (max_diff > 20) begin
                    print_du(rg_mcu_in, "DU_t input", BLUE);
                    print_du(ref_, "DU_t reference output", CYAN);
                    print_du(res_tp, "DU_t DUT output", YELLOW);
                    print_fmt($format("Error>20 at iteration %d", rg_counter), RED);
                    rg_errors <= rg_errors + 1;
                end
            endaction
            rg_counter <= rg_counter + 1;
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
