package TestImageTiling;

import StmtFSM :: *;
import ClientServer :: *;
import GetPut :: *;
import Connectable :: *;
import List :: *;
import Vector :: *;
import BlueAXI :: *;

import BDPI :: *;
import Types :: *;
import PrintUtil :: *;
import TestHelper :: *;
import SimRAM_AXI :: *;
import ImageTilingEngine :: *;

module [Module] mkTestImageTiling(TestHandler_ifc);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t_single <- mkTestCase(False, 128);
    let t_double <- mkTestCase(True, 128);
    let t_hd_single <- mkTestCase(False, 1920);
    let t_hd_double <- mkTestCase(True, 1920);
    let t_narrow <- mkTestCase(True, 8);

    Stmt s = seq
        t_single.go();
        while(!t_single.done()) action endaction
        t_double.go();
        while(!t_double.done()) action endaction
        t_hd_single.go();
        await(t_hd_single.done());
        t_hd_double.go();
        await(t_hd_double.done());
        t_narrow.go();
        await(t_narrow.done());
    endseq;

    FSM i_test_fsm <- mkFSM(s);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

module [Module] mkTestCase#(Bool double_buffer, Integer img_width)(TestHandler_ifc)
    provisos(
        NumAlias#(8, mcu_w),
        NumAlias#(8, mcu_h),
        Mul#(mcu_w, mcu_h, pixels_in_mcu)
    );

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    NumProxy_t#(1920) max_width = ?;

    ImageTilingEngine_ifc#(Bit#(24), mcu_w, mcu_h) dut <- mkImageTilingEngine(max_width, double_buffer);

    Reg#(UInt#(24)) rg_counter_in <- mkReg(0);

    Reg#(UInt#(24)) rg_block_counter <- mkReg(0);
    Reg#(UInt#(24)) rg_pix_counter   <- mkReg(0);

    Integer blocks_per_row = img_width/valueof(mcu_w);
    /* Amount of rows of blocks of pixels to mkTestCase */
    Integer test_rows = 4;

    Stmt s = seq
        dut.set_img_width(fromInteger(img_width));
        dut.start();
        par
            while(rg_counter_in < fromInteger(test_rows*img_width*valueof(mcu_h))) action
                /* feed dummy pixels to dut */
                dut.line_in.put(pack(rg_counter_in));
                rg_counter_in <= rg_counter_in + 1;
            endaction
            seq
                /* Double-buffered mode must accept two complete line groups before output drains. */
                if(double_buffer)
                    await(rg_counter_in >= fromInteger(2*img_width*valueof(mcu_h)));
                while(rg_block_counter < fromInteger(test_rows*blocks_per_row)) seq
                    while(rg_pix_counter < fromInteger(valueof(pixels_in_mcu))) action
                        let pix     <- dut.block_out.get();
                        let block_x = rg_pix_counter % 8;
                        let block_y = rg_pix_counter / 8;
                        let row     = rg_block_counter / fromInteger(blocks_per_row);
                        let col     = rg_block_counter % fromInteger(blocks_per_row);
                        let exp     = row*fromInteger(blocks_per_row*valueof(pixels_in_mcu))+col*fromInteger(valueof(mcu_w)) + fromInteger(img_width)*block_y + block_x;
                        if(unpack(pix) != exp) begin
                            print_fmt($format("Got %d expected %d", pix, exp), RED);
                            $finish();
                        end else begin
                            // print_fmt($format("Pixel #%0d, %0d", rg_pix_counter, exp), BLUE);
                        end
                        rg_pix_counter <= rg_pix_counter + 1;
                    endaction
                    action
                        rg_block_counter <= rg_block_counter + 1;
                        rg_pix_counter <= 0;
                    endaction
                endseq
            endseq
        endpar
        print_s("Finished successfully", GREEN);
    endseq;

    FSM i_test_fsm <- mkFSM(s);

    method Action go();
        i_test_fsm.start();
    endmethod

    method Bool done();
        return i_test_fsm.done();
    endmethod

endmodule

endpackage
