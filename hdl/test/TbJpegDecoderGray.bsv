package TbJpegDecoderGray;

import TestHelper :: *;
import TbJpegDecoder :: *;

//decoder configuration: grayscale-only, raster output with a single line buffer
module [Module] mkTbJpegDecoderGray(TestHandler_ifc);
    let ifc <- mkTbJpegDecoderCase(True, False, False, False);
    return ifc;
endmodule

endpackage
