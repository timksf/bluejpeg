package BlueJPEGRegs;

import FIFO :: *;
import GetPut :: *;
import SpecialFIFOs :: *;
import BlueCSRCore :: *;

import Types :: *;
import TableStorage :: *;
import EncoderUtil :: *;

typedef struct {
    TableType_t table_type;
    Bit#(8)     addr;
    Bit#(32)    data;
} TableWriteCmd_t deriving(Bits, Eq, FShow);

interface PerfCounter_ifc;
    method Action tick();
endinterface

//read-only 32-bit event counter owned by a single rule
//clear restarts it at the event of the same cycle, so no tick is lost
module [BlueCSRCtx_t#(32, 32)] perf_counter#(Integer offs, Bool clear, String ident, String name, String desc)(PerfCounter_ifc);
    PulseWire               pw_tick  <- mkPulseWire;
    Wire#(Maybe#(Bit#(32))) w_update <- mkDWire(tagged Invalid);

    ReadOnly#(Bit#(32)) rg_count <- csr_reg_ho(offs, 0, 0, w_update, ident, name, desc);

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_update (clear || pw_tick);
        Bit#(32) base = clear ? 0 : rg_count;
        w_update <= tagged Valid (base + (pw_tick ? 1 : 0));
    endrule

    method tick = pw_tick.send;
endmodule

interface BlueJPEGCfg_ifc;
    method Action clear_start();
    method Action clear_done();
    method Action finish();
    method Action invalid_cfg();
    method Action table_sts(Bool ready, Bool cg_active);
    method Action clear_cg_trig();
    method Action perf_rst();

    interface PerfCounter_ifc               perf_cycles;
    interface PerfCounter_ifc               perf_pixels;
    interface PerfCounter_ifc               perf_byteso;
    interface PerfCounter_ifc               perf_idle;
    interface PerfCounter_ifc               perf_flush;
    interface PerfCounter_ifc               perf_frame;
    interface PerfCounter_ifc               perf_boot;

    interface ReadOnly#(Bool)               start;
    interface ReadOnly#(Bit#(16))           img_width;
    interface ReadOnly#(Bit#(16))           img_height;
    interface ReadOnly#(Bool)               codegen_trig;
    interface ReadOnly#(HuffTableType_t)    codegen_type;

    interface Get#(TableWriteCmd_t)         table_write;
endinterface

module [BlueCSRCtx_t#(32, 32)] blue_jpeg_csrs(BlueJPEGCfg_ifc);

    ReadOnly#(Bool)    rg_start;
    ReadOnly#(Bit#(1)) rg_done;

    PulseWire pw_frame_done <- mkPulseWire;
    PulseWire pw_inv_cfg    <- mkPulseWire;
    PulseWire pw_perf_rst   <- mkPulseWire;

    PulseWire              pw_clear_start   <- mkPulseWire;
    PulseWire              pw_clear_cg_trig <- mkPulseWire;
    Wire#(Maybe#(Bit#(1))) w_done_update    <- mkDWire(tagged Invalid);

    Reg#(Bool) rg_ready;
    Reg#(Bool) rg_cg_busy;

    ReadOnly#(Bool)       rg_cg_trigger;
    Reg#(HuffTableType_t) rg_cg_table_t;

    Reg#(Bit#(16)) rg_imw;
    Reg#(Bit#(16)) rg_imh;

    PerfCounter_ifc i_perf_cycles;
    PerfCounter_ifc i_perf_pixels;
    PerfCounter_ifc i_perf_byteso;
    PerfCounter_ifc i_perf_idle;
    PerfCounter_ifc i_perf_flush;
    PerfCounter_ifc i_perf_frame;
    PerfCounter_ifc i_perf_boot;

    FIFO#(TableWriteCmd_t) f_fn_table_write <- mkFIFO;

    //writes table table_t at local address offs with value val
    function Action fn_table_write(TableType_t table_t, Bit#(32) offs, Bit#(32) val);
        action
            //offs is still a BYTE offset into the 32bit table region
            //to get an index as required by TableStorage, divide by 4
            f_fn_table_write.enq(
                TableWriteCmd_t {
                    table_type: table_t,
                    addr:       truncate(offs >> 2),
                    data:       val
                }
            );
        endaction
    endfunction

    function Bit#(32) fn_table_read(TableType_t table_t, Bit#(32) offs);
        //TODO
        return 0;
    endfunction

    csr_regmap_def("BlueJPEG", "Register File for BlueJPEG encoder.");

    //an ID register is usefuls in designs with many peripherals
    csr_reg_def('h00, "MIV", "Module ID & Version Register.");
    csr_reg_rc('h00, Bit#(12)'('h001),   0, "MID", "Module ID",      "Unique ID for this module.");
    csr_reg_rc('h00, Bit#(3)'('h0),     16, "VRS", "Module Version", "Module version.");


    csr_reg_def('h04, "CTRL", "Control Register.");
    rg_start <- csr_reg_hu(
        'h04, False, 0, pw_clear_start ? tagged Valid False : tagged Invalid,
        "START", "Module Start", "Writing 1 requests processing. Hardware clears the request when it is accepted or rejected."
    );


    csr_reg_def('h08, "STS", "Status Register.");
    rg_ready    <- csr_reg_ro( 'h08, False,   0, "RDY",   "Module Ready",    "Set once the default tables are loaded and their Huffman codes generated after reset. Low while a codegen runs.");
    rg_cg_busy  <- csr_reg_ro( 'h08, False,   1, "CGB",   "Codegen Busy",    "Indicates whether huffman table codegen is running.");
    rg_done     <- csr_reg_ho(
        'h08, 'b0, 4, w_done_update,
        "DONE", "Module Done", "Set on frame completion and cleared when a new frame is accepted."
    );


    csr_reg_def('h0C, "IMSZ", "Image Size.");
    rg_imw <- csr_reg_rw('h0C, 0,  0, "IMW", "Image Width",   "");
    rg_imh <- csr_reg_rw('h0C, 0, 16, "IMH", "Image Height",  "");


    csr_reg_def('h14, "CGEN", "Huffman Codegen Config.");
    rg_cg_table_t <- csr_reg_rw( 'h14, unpack(0),    0, "TBL", "CG Table Type",     "Controls which table type to generate. 00=DC LUMA, 01=DC CHROMA, 10=AC LUMA, 11=AC CHROMA.");
    rg_cg_trigger <- csr_reg_hu(
        'h14, False, 31, pw_clear_cg_trig ? tagged Valid False : tagged Invalid,
        "TRG", "Codegen Trigger", "Writing 1 triggers Huffman code generation from the stored tables. Hardware clears it when the codegen starts."
    );


    //pending bits latch regardless of enable and double as sticky status
    //enabled pending bits drive the irq line
    csr_reg_def('h18, "IRQP", "Interrupt Pending (W1C).");
    csr_reg_def('h1C, "IRQE", "Interrupt Enable.");
    csr_irq('h18, 'h1C, 0, 0, pw_frame_done, "DONE", "Frame Done",     "A frame was encoded completely.");
    csr_irq('h18, 'h1C, 1, 0, pw_inv_cfg,    "INV",  "Invalid Config", "A start request was rejected because of an invalid image size.");


    csr_reg_def('h30, "PERF0", "Performance Counter Cycles.");
    i_perf_cycles <- perf_counter('h30, pw_perf_rst, "CYC", "Cycle Counter", "Number of cycles in running state since last processing start.");


    csr_reg_def('h34, "PERF1", "Performance Counter Pixels.");
    i_perf_pixels <- perf_counter('h34, pw_perf_rst, "PIX", "Pixel Counter", "Number of pixels processed since last processing start.");


    csr_reg_def('h38, "PERF2", "Performance Counter Bytes.");
    i_perf_byteso <- perf_counter('h38, pw_perf_rst, "BYTEO", "Out Byte Counter", "Number of encoded bytes produced since last processing start.");


    csr_reg_def('h3C, "PERF3", "Performance Counter Idle Cycles.");
    i_perf_idle <- perf_counter('h3C, pw_perf_rst, "IDLE", "Idle Cycles", "Cycles in running state in which no input pixel was accepted.");


    csr_reg_def('h40, "PERF4", "Performance Counter Flush Cycles.");
    i_perf_flush <- perf_counter('h40, pw_perf_rst, "FLSH", "Flush Cycles", "Cycles from the last data unit entering the pipeline until the frame is done.");


    csr_reg_def('h44, "PERF5", "Performance Counter Frame Cycles.");
    i_perf_frame <- perf_counter('h44, pw_perf_rst, "FRAME", "Frame Cycles", "Cycles from the accepted start request until the frame is done, including configuration.");


    csr_reg_def('h48, "PERF6", "Performance Counter Boot Cycles.");
    i_perf_boot <- perf_counter('h48, False, "BOOT", "Boot Cycles", "Cycles from reset until the default tables and Huffman codes were first ready.");

    csr_region_rw('h100,  256, fn_table_read(QLuma),          fn_table_write(QLuma),          "QLUMAR",   "Raw luma quantization table, used for bitstream generation.");
    csr_region_rw('h200,  256, fn_table_read(QChroma),        fn_table_write(QChroma),        "QCHROMAR", "Raw chroma quantization table, used for bitstream generation.");
    csr_region_rw('h300,  256, fn_table_read(QLumaScaled),    fn_table_write(QLumaScaled),    "QLUMASC",  "Scaled luma quantization table, used during encoding.");
    csr_region_rw('h400,  256, fn_table_read(QChromaScaled),  fn_table_write(QChromaScaled),  "QCHROMASC","Scaled chroma quantization table, used during encoding.");

    csr_region_rw('h500,   64, fn_table_read(HuffbitsLumaDC),   fn_table_write(HuffbitsLumaDC),   "HBITSDCL", "HUFFBITS table for DC luma components.");
    csr_region_rw('h540,   64, fn_table_read(HuffbitsChromaDC), fn_table_write(HuffbitsChromaDC), "HBITSDCC", "HUFFBITS table for DC chroma components.");
    csr_region_rw('h580,   64, fn_table_read(HuffbitsLumaAC),   fn_table_write(HuffbitsLumaAC),   "HBITSACL", "HUFFBITS table for AC luma components.");
    csr_region_rw('h5C0,   64, fn_table_read(HuffbitsChromaAC), fn_table_write(HuffbitsChromaAC), "HBITSACC", "HUFFBITS table for AC chroma components.");

    csr_region_rw('h1000, 1024, fn_table_read(HuffvalLumaDC),   fn_table_write(HuffvalLumaDC),   "HVALDCL",  "HUFFVAL table for DC luma components.");
    csr_region_rw('h1400, 1024, fn_table_read(HuffvalChromaDC), fn_table_write(HuffvalChromaDC), "HVALDCC",  "HUFFVAL table for DC chroma components.");
    csr_region_rw('h1800, 1024, fn_table_read(HuffvalLumaAC),   fn_table_write(HuffvalLumaAC),   "HVALACL",  "HUFFVAL table for AC luma components.");
    csr_region_rw('h1C00, 1024, fn_table_read(HuffvalChromaAC), fn_table_write(HuffvalChromaAC), "HVALACC",  "HUFFVAL table for AC chroma components.");

    method perf_rst         = pw_perf_rst.send;

    method table_sts(r, c)  = action rg_ready <= r; rg_cg_busy <= c; endaction;
    method invalid_cfg      = pw_inv_cfg.send;
    method clear_start      = pw_clear_start.send;
    method clear_done       = action w_done_update <= tagged Valid 0; endaction;
    method finish           = action w_done_update <= tagged Valid 1; pw_frame_done.send; endaction;
    method clear_cg_trig    = pw_clear_cg_trig.send;

    interface start         = rg_start;
    interface img_width     = reg_to_read_only(rg_imw);
    interface img_height    = reg_to_read_only(rg_imh);
    interface codegen_trig  = rg_cg_trigger;
    interface codegen_type  = reg_to_read_only(rg_cg_table_t);

    interface perf_cycles   = i_perf_cycles;
    interface perf_pixels   = i_perf_pixels;
    interface perf_byteso   = i_perf_byteso;
    interface perf_idle     = i_perf_idle;
    interface perf_flush    = i_perf_flush;
    interface perf_frame    = i_perf_frame;
    interface perf_boot     = i_perf_boot;

    interface table_write   = toGet(f_fn_table_write);

endmodule

endpackage
