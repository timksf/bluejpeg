package TbEncoderThroughputShallow;

import TbEncoderThroughput :: *;
import TestHelper :: *;

//DCT at one eighth of the main clock with two register stages per pass
module [Module] mkTbEncoderThroughputShallow(TestHandler_ifc);
    let i_test <- mkEncoderThroughput(8, True);
    return i_test;
endmodule

endpackage
