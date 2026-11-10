package TestGenPatternRom;

import StmtFSM :: *;

import BDPI :: *;
import JpegTestRegs :: *;
import PrintUtil :: *;
import TestHelper :: *;

String input_image_path = `ASSETS_DIR + "/sample_192x192.bmp";
String output_rom_path  = "pattern_192x192.gen";

/*
 * Writes the test system's pattern ROM image: the sample image converted to YCbCr with
 * the same loader and reference conversion as the encoder tests, one {Y, Cb, Cr} word per
 * line in raster order. `make rom` copies the result to rom/pattern_192x192.mem.
 */
module [Module] mkTestGenPatternRom(TestHandler_ifc)
    provisos(
        NumAlias#(n_pixels, PatternPixels)
    );
    function print_s = print_mod_pre_color_t_s;

    Reg#(UInt#(64)) rg_ram_ptr   <- mkRegU;
    Reg#(UInt#(64)) rg_img_ptr   <- mkRegU;
    Reg#(File)      rg_file      <- mkRegU;
    Reg#(UInt#(32)) rg_pixel_idx <- mkReg(0);

    Stmt s = seq
        action
            let ram <- create_SimRAM(fromInteger(valueOf(n_pixels)), 4);
            rg_ram_ptr <= ram;
        endaction
        action
            let img <- create_ImageLoader(input_image_path);
            rg_img_ptr <= img;
        endaction
        write_to_mem_interleaved_ImageLoader(rg_img_ptr, rg_ram_ptr, 0);
        action
            let fd <- $fopen(output_rom_path, "w");
            if(fd == InvalidFile) begin
                print_s("ERROR: cannot open the ROM output file", RED);
                $finish(1);
            end
            rg_file <= fd;
        endaction
        for(rg_pixel_idx <= 0; rg_pixel_idx < fromInteger(valueOf(n_pixels)); rg_pixel_idx <= rg_pixel_idx + 1) action
            let word <- read_word_SimRAM(rg_ram_ptr, extend(rg_pixel_idx));
            Bit#(24) rgb   = truncate(pack(word));
            Bit#(32) ycbcr = rgb2ycbcr_ref(unpack(rgb[23:16]), unpack(rgb[15:8]), unpack(rgb[7:0]));
            $fwrite(rg_file, "%06h\n", ycbcr[23:0]);
        endaction
        $fclose(rg_file);
        print_s("Pattern ROM written to " + output_rom_path, GREEN);
    endseq;

    FSM i_fsm <- mkFSM(s);

    method Action go();
        i_fsm.start();
    endmethod

    method Bool done();
        return i_fsm.done();
    endmethod
endmodule

endpackage
