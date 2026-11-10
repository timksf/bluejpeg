package TestHelper;

import BDPI :: *;

interface TestHandler_ifc;
    method Action go();
    method Bool done();
endinterface

//random 8-bit sample from the C++ reference generator
function ActionValue#(UInt#(8)) rand_pix() = actionvalue
    let v <- rand_i16(0, 255);
    return truncate(unpack(v));
endactionvalue;

endpackage
