package TestRLE;

import FIFO :: *;
import Vector :: *;
import GetPut :: *;
import StmtFSM :: *;
import ClientServer :: *;

import BDPI :: *;
import Util :: *;
import Types :: *;
import RLE :: *;
import PrintUtil :: *;
import TestHelper :: *;

import "BDPI" function ActionValue#(Bit#(64)) rle_model_create();
import "BDPI" function Action rle_model_destroy(Bit#(64) ptr);
import "BDPI" function Action rle_model_set_mode(Bit#(64) ptr, Bit#(8) mode);
import "BDPI" function Action rle_model_rewind(Bit#(64) ptr);
import "BDPI" function Action rle_model_process_block(Bit#(1024) input_packed, Bit#(64) ptr);

import "BDPI" function ActionValue#(Bit#(8))  rle_model_has_next(Bit#(64) ptr);
import "BDPI" function ActionValue#(Bit#(8))  rle_model_next_type(Bit#(64) ptr);
import "BDPI" function ActionValue#(Int#(16)) rle_model_next_val(Bit#(64) ptr);
import "BDPI" function ActionValue#(Bit#(8))  rle_model_next_run(Bit#(64) ptr);
import "BDPI" function Action rle_model_pop(Bit#(64) ptr);

typedef 14 DPw;

module [Module] mkTestRLE(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    Bool verbose = True;

    RLE_ifc#(DPw) dut <- mkRLE;
    
    Reg#(Bit#(64)) ref_ptr <- mkReg(0);
    Reg#(Bit#(32)) rg_counter <- mkReg(0);
    Reg#(Bit#(32)) rg_errors <- mkReg(0);

    Reg#(Bit#(7)) rg_count_in  <- mkReg(0);
    Reg#(Bool)    rg_has_next  <- mkReg(False);
    
    Reg#(Vector#(64, Int#(DPw))) rg_block_in <- mkRegU;

    Stmt test_seq = seq
        action
            let ptr <- rle_model_create();
            ref_ptr <= ptr;
        endaction

        dut.rewind();
        rle_model_rewind(ref_ptr);

        while(rg_counter < 40) seq
            action
                //alternate between comp 0 (Y) and comp 1 (Cb) to verify independent DPCM tracking
                Bit#(2) comp = (rg_counter % 2 == 0) ? 0 : 1;
                dut.du_comp.put(comp);
                rle_model_set_mode(ref_ptr, (comp == 0) ? 0 : 1);
            endaction

            action
                Vector#(64, Int#(DPw)) block_1d = newVector;
                Vector#(32, Bit#(32)) input_packed = newVector;
                Vector#(64, Int#(16)) ref_input = newVector;

                for(Integer i=0; i<64; i=i+1) begin
                    let rand_val <- rand_pix();
                    let is_zero <- rand_pix();
                    
                    //force ~78% zeros (200/255) for all AC values to thoroughly test AC runs, ZRL, and EOB
                    Int#(16) val = (is_zero < 200 && i > 0) ? 0 : unpack(zeroExtend(pack(rand_val)) - 128);
                    
                    block_1d[i]  = truncate(val);
                    ref_input[i] = val;
                end
                
                rg_block_in <= block_1d;
                rle_model_process_block(pack(ref_input), ref_ptr);
                if(verbose)
                    print_fmt($format("Input: ") + fshow(block_1d), YELLOW);
            endaction
            
            rg_count_in <= 0;
            
            par
                //feed DUT sequentially
                while(rg_count_in < 64) action
                    dut.data.request.put(rg_block_in[rg_count_in]);
                    rg_count_in <= rg_count_in + 1;
                endaction

                seq
                    action
                        let has_n <- rle_model_has_next(ref_ptr);
                        rg_has_next <= (has_n != 0);
                    endaction
                    while(rg_has_next) seq
                        action
                            let dut_tag <- dut.data.response.get();
                            
                            Bit#(8)  ref_type <- rle_model_next_type(ref_ptr);
                            Int#(16) ref_val  <- rle_model_next_val(ref_ptr);
                            Bit#(8)  ref_run  <- rle_model_next_run(ref_ptr);

                            //manual unmapping
                            RLETag_t#(DPw) ref_tag = case(ref_type)
                                0: tagged DCDiff truncate(ref_val);
                                1: tagged EOB;
                                2: tagged ZRL;
                                3: tagged AC ACRun_t { run: truncate(ref_run), val: truncate(ref_val) };
                            endcase;
                            
                            if(verbose) begin
                                print_fmt($format("DUT: ") + fshow(dut_tag), CYAN);
                            end

                            if (dut_tag != ref_tag) begin
                                print_fmt($format("Mismatch at block %d! DUT: ", rg_counter) + fshow(dut_tag) + $format(" vs REF: ") + fshow(ref_tag), RED);
                                rg_errors <= rg_errors + 1;
                            end
                            rle_model_pop(ref_ptr);
                        endaction
                        action
                            let has_n <- rle_model_has_next(ref_ptr);
                            rg_has_next <= (has_n != 0);
                        endaction
                    endseq
                endseq
            endpar
            
            rg_counter <= rg_counter + 1;
        endseq
        
        action
            if (rg_errors == 0) print_s("mkRLE PASSED", GREEN);
            else print_fmt($format("mkRLE FAILED with %d errors", rg_errors), RED);
            rle_model_destroy(ref_ptr);
        endaction
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