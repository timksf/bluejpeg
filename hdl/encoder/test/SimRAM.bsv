package SimRAM;

import ClientServer :: *;
import FIFO :: *;
import FIFOF :: *;
import GetPut :: *;

import BDPI :: *;

interface SimRAMSimple_ifc;
    method Action set_ram(UInt#(64) ptr);
    method UInt#(64) get_ram();
    method ActionValue#(UInt#(64)) read(UInt#(64) addr);
    method Action write(UInt#(64) addr, UInt#(64) data);
    method Action write_strobe(UInt#(64) addr, UInt#(64) data, UInt#(64) strobe);
    method ActionValue#(UInt#(64)) read_byte(UInt#(64) byte_addr);
    method Action write_byte(UInt#(64) byte_addr, UInt#(64) byte_val);
endinterface

module mkSimRAM_simple(SimRAMSimple_ifc);

    Reg#(Maybe#(UInt#(64))) m_ptr <- mkReg(tagged Invalid);

    method get_ram if(m_ptr matches tagged Valid .p) = p;
    method set_ram(d) = action m_ptr <= tagged Valid d; endaction;
    method read(a)               if(m_ptr matches tagged Valid .ptr) = read_word_SimRAM(ptr, a);
    method write(a, d)           if(m_ptr matches tagged Valid .ptr) = write_word_SimRAM(ptr, a, d);
    method write_strobe(a, d, s) if(m_ptr matches tagged Valid .ptr) = write_strobe_SimRAM(ptr, a, d, s);
    method read_byte(a)          if(m_ptr matches tagged Valid .ptr) = read_byte_SimRAM(ptr, a);
    method write_byte(a, d)      if(m_ptr matches tagged Valid .ptr) = write_byte_SimRAM(ptr, a, d);

endmodule

endpackage