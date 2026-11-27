package TbJpegDecoderBlocks;

import TestHelper :: *;
import TbJpegDecoder :: *;
import DecoderTypes :: *;

//decoder configuration: color with block-order output
module [Module] mkTbJpegDecoderBlocks(TestHandler_ifc);
    let ifc <- mkTbJpegDecoderCase(False, False, True, False, Sub444, False, False);
    return ifc;
endmodule

endpackage
