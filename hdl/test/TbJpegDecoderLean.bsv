package TbJpegDecoderLean;

import TestHelper :: *;
import TbJpegDecoder :: *;
import DecoderTypes :: *;

//decoder configuration: colour up to 4:2:2 with the resource options, shallow IDCT passes and fixed standard Huffman tables
module [Module] mkTbJpegDecoderLean(TestHandler_ifc);
    let ifc <- mkTbJpegDecoderCase(True, True, True, False, Sub422, True, True);
    return ifc;
endmodule

endpackage
