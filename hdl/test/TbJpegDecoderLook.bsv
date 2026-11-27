package TbJpegDecoderLook;

import TestHelper :: *;
import TbJpegDecoder :: *;
import DecoderTypes :: *;

//decoder configuration: colour up to 4:2:2 with Huffman lookahead tables, raster output with double buffering
module [Module] mkTbJpegDecoderLook(TestHandler_ifc);
    let ifc <- mkTbJpegDecoderCase(True, True, True, True, Sub422);
    return ifc;
endmodule

endpackage
