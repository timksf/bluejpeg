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

module [Module] mkTestImageTiling(TestHandler);

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    let t_single <- test(False);
    let t_double <- test(True);

    Stmt s = seq
        t_single.go();
        while(!t_single.done()) action endaction
        t_double.go();
        while(!t_double.done()) action endaction
    endseq;

    FSM testFSM <- mkFSM(s);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod

endmodule

module [Module] test#(Bool double_buffer)(TestHandler) provisos(
        NumAlias#(8, mcu_w),
        NumAlias#(8, mcu_h),
        Mul#(mcu_w, mcu_h, pixels_in_mcu)
    );

    function print_s = print_mod_pre_color_t_s;
    function print_fmt = print_mod_pre_color_t_f;

    NumProxy#(640) max_width = ?;

    ImageTilingEngine_ifc#(Bit#(24), mcu_w, mcu_h) dut <- mkImageTilingEngine(max_width, double_buffer);

    Reg#(UInt#(24)) rCounterIn <- mkReg(0);

    Reg#(UInt#(24)) rBlockCounter <- mkReg(0);
    Reg#(UInt#(24)) rPixCounter <- mkReg(0);

    Integer img_width = 128;
    Integer blocks_per_row = img_width/valueof(mcu_w);
    /* Amount of rows of blocks of pixels to test */
    Integer test_rows = 4;

    Stmt s = seq
        dut.set_img_width(fromInteger(img_width));
        dut.start();
        par
            while(rCounterIn < fromInteger(test_rows*img_width*valueof(mcu_h))) action
                /* feed dummy pixels to dut */
                dut.line_in.put(pack(rCounterIn));
                rCounterIn <= rCounterIn + 1;
            endaction
            seq
                /* Double-buffered mode must accept two complete line groups before output drains. */
                if(double_buffer)
                    await(rCounterIn >= fromInteger(2*img_width*valueof(mcu_h)));
                while(rBlockCounter < fromInteger(test_rows*blocks_per_row)) seq
                    while(rPixCounter < fromInteger(valueof(pixels_in_mcu))) action
                        let pix <- dut.block_out.get();
                        let block_x = rPixCounter % 8;
                        let block_y = rPixCounter / 8;
                        let row = rBlockCounter / fromInteger(blocks_per_row);
                        let col = rBlockCounter % fromInteger(blocks_per_row);
                        let exp = row*fromInteger(blocks_per_row*valueof(pixels_in_mcu))+col*fromInteger(valueof(mcu_w)) + fromInteger(img_width)*block_y + block_x;
                        if(unpack(pix) != exp) begin
                            print_fmt($format("Got %d expected %d", pix, exp), RED);
                            $finish();
                        end else begin
                            // print_fmt($format("Pixel #%0d, %0d", rPixCounter, exp), BLUE);
                        end
                        rPixCounter <= rPixCounter + 1;
                    endaction
                    action
                        rBlockCounter <= rBlockCounter + 1;
                        rPixCounter <= 0;
                    endaction
                endseq
            endseq
        endpar
        print_s("Finished successfully", GREEN);
    endseq;

    FSM testFSM <- mkFSM(s);

    method Action go();
        testFSM.start();
    endmethod

    method Bool done();
        return testFSM.done();
    endmethod

endmodule

endpackage
