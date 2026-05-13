package BlueJPEGRegs;

import BlueCSR :: *;

interface BlueJPEGCfg_ifc;
    method Action finish();
    method Action set_status(Bool tables_ready, Bool codegen_busy);
    method Action clear_codegen_trigger();

    method Action perf_rst();
    method Action perf_cycles_incr();
    method Action perf_pixels_incr();

    interface ReadOnly#(Bool) start;
    interface ReadOnly#(Bit#(16)) img_width;
    interface ReadOnly#(Bit#(16)) img_height;
    interface ReadOnly#(SubsamplingMode_t) subsampling;
    interface ReadOnly#(Bit#(32)) codegen;

    interface Get#(TableWriteCmd_t) table_write;
endinterface

module [BlueCSRCtx_t#(32, 32)] blueJPEGConfig(BlueJPEGCfg_ifc);

    Reg#(Bit#(1))           rg_start;
    Reg#(Bit#(1))           rg_done;
    Reg#(Bit#(1))           rg_error;

    Reg#(Bit#(1))           rg_ready;
    Reg#(Bit#(1))           cg_busy;

    Reg#(Bit#(1))           rg_cg_trigger;
    Reg#(HuffTableType_t)   rg_cg_table_t;

    Reg#(Bit#(16))          rg_imw;
    Reg#(Bit#(16))          rg_imh;

    csr_regmap_def("BlueJPEG", "Register File for BlueJPEG encoder.");

    
    //an ID register is usefuls in designs with many peripherals
    csr_reg_def('h00, "MIV", "Module ID and version register.");
    csr_reg_rc('h00, Bit#(12)'('h001),   0, "MID", "Module ID",      "Unique ID for this module.");
    csr_reg_rc('h00, Bit#(3)'('h0),     16, "VRS", "Module Version", "Module verion.");


    csr_reg_def('h04, "CTRL", "Control register.");
    rg_start <- csr_reg_rw('h04, 0, "START", "Module Start", "Writing a 1 kicks off processing if codegen is finished.");
    

    csr_reg_def('h08, "STS", "Status register.");
    rg_ready    <- csr_reg_ro( 'h08,     0, "RDY",   "Module Ready",    "Indicates whether module is ready for processing.");
    cg_busy     <- csr_reg_ro( 'h08,     1, "CGB",   "Codegen Busy",    "Indicates whether huffman table codegen is running.");
    rg_done     <- csr_reg_ro( 'h08,     4, "DONE",  "Module Done",     "Indicates whether processing has finished for current image.");
    rg_error    <- csr_reg_w1c('h08,    16, "ERR",   "Module Error",    "Indicates whether an error occurred processing the current image.");


    csr_reg_def('h0C, "IMSZ", "Image size.");
    rg_imw <- csr_reg_rw('h0C,   0, "IMW", "Image Width",   "");
    rg_imh <- csr_reg_rw('h0C,  16, "IMH", "Image Height",  "");
    

    csr_reg_def('h14, "CGEN", "Huffman Codegen Config.");
    rg_cg_table_t <- csr_reg_rw( 'h14,   0, "TBL", "CG Table Type",     "Controls which table type to generate. 00=DC LUMA, 01=DC CHROMA, 10=AC LUMA, 11=AC CHROMA.");
    rg_cg_trigger <- csr_reg_w1s('h14,  31, "TRG", "Codegen Trigger",   "Writing 1 triggers huffman code generation from stored tables.");


endmodule

endpackage