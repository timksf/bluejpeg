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

    csr_regmap_def("BlueJPEG", "Register File for BlueJPEG encoder.");

endmodule

endpackage