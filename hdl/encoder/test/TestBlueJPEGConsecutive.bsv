package TestBlueJPEGConsecutive;

import TestBlueJPEGGrayConsecutive :: *;
import TestHelper :: *;

module [Module] mkTestBlueJPEGConsecutive(TestHandler_ifc);
    let i_test <- mkBlueJPEGConsecutiveTest(True, True);
    return i_test;
endmodule

endpackage
