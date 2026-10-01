package TestBlueJPEGConsecutive;

import TestBlueJPEGGrayConsecutive :: *;
import TestHelper :: *;

module [Module] mkTestBlueJPEGConsecutive(TestHandler);
    let test <- mkBlueJPEGConsecutiveTest(True, True);
    return test;
endmodule

endpackage
