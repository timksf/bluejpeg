package TbEncoderThroughputDiv8;

import TbEncoderThroughput :: *;
import TestHelper :: *;

module [Module] mkTbEncoderThroughputDiv8(TestHandler_ifc);
    let i_test <- mkEncoderThroughput(8, False);
    return i_test;
endmodule

endpackage
