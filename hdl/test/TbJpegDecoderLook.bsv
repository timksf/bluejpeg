package TbJpegDecoderLook;

import TestHelper :: *;
import TbJpegDecoder :: *;

//decoder configuration: colour with Huffman lookahead tables, raster output with double buffering
module [Module] mkTbJpegDecoderLook(TestHandler_ifc);
    let ifc <- mkTbJpegDecoderCase(True, True, True, True);
    return ifc;
endmodule

endpackage
