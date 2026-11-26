package TbJpegDecoderBlocks;

import TestHelper :: *;
import TbJpegDecoder :: *;

//decoder configuration: color with block-order output
module [Module] mkTbJpegDecoderBlocks(TestHandler_ifc);
    let ifc <- mkTbJpegDecoderCase(False, False, True, False);
    return ifc;
endmodule

endpackage
