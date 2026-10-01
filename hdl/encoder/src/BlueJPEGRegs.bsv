package BlueJPEGRegs;

import FIFO :: *;
import GetPut :: *;
import SpecialFIFOs :: *;

import BlueCSRCore :: *;

import Types :: *;
import TableStorage :: *;
import Util :: *;

typedef struct {
    TableType_t table_type;
    Bit#(8)     addr;
    Bit#(32)    data;
} TableWriteCmd_t deriving(Eq, Bits, FShow);

interface PerfCounter_ifc#(numeric type n);
    method Action load(Bit#(n) v);
    method Action tick_up();
    method Action tick_dn();
endinterface

function PerfCounter_ifc#(n) reg_to_perfc(Reg#(Bit#(n)) r);
    return interface PerfCounter_ifc;
        method load     = r._write;
        method tick_up  = action r <= r+1; endaction;
        method tick_dn  = action r <= r-1; endaction; 
    endinterface;
endfunction

interface BlueJPEGCfg_ifc;
    method Action finish();
    method Action error();
    method Action invalid_cfg();
    method Action table_sts(Bool ready, Bool cg_active);
    method Action clear_cg_trig();
    method Action perf_rst();

    interface PerfCounter_ifc#(32)          perf_cycles;
    interface PerfCounter_ifc#(32)          perf_pixels;
    interface PerfCounter_ifc#(32)          perf_byteso;

    interface ReadOnly#(Bool)               start;
    interface ReadOnly#(Bit#(16))           img_width;
    interface ReadOnly#(Bit#(16))           img_height;
    interface ReadOnly#(Bool)               codegen_trig;
    interface ReadOnly#(HuffTableType_t)    codegen_type;

    interface Get#(TableWriteCmd_t)         table_write;
endinterface

module [BlueCSRCtx_t#(32, 32)] blue_jpeg_csrs(BlueJPEGCfg_ifc);

    Reg#(Bool)              rg_start;
    Reg#(Bit#(1))           rg_done;
    ReadOnly#(Bit#(1))      rg_error;
    ReadOnly#(Bool)         rg_inv_cfg;

    PulseWire               pw_error   <- mkPulseWire;
    PulseWire               pw_inv_cfg <- mkPulseWire;

    Reg#(Bool)              rg_ready;
    Reg#(Bool)              rg_cg_busy;

    Reg#(Bool)              rg_cg_trigger;
    Reg#(HuffTableType_t)   rg_cg_table_t;

    Reg#(Bit#(16))          rg_imw;
    Reg#(Bit#(16))          rg_imh;

    Reg#(Bit#(32))          rg_perf_cycles;
    Reg#(Bit#(32))          rg_perf_pixels;
    Reg#(Bit#(32))          rg_perf_byteso;

    FIFO#(TableWriteCmd_t)  f_fn_table_write <- mkFIFO;

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
    csr_reg_rc('h00, Bit#(3)'('h0),     16, "VRS", "Module Version", "Module verion.");


    csr_reg_def('h04, "CTRL", "Control Register.");
    rg_start <- csr_reg_rw('h04, False, 0, "START", "Module Start", "Writing a 1 kicks off processing if codegen is finished.");
    

    csr_reg_def('h08, "STS", "Status Register.");
    rg_ready    <- csr_reg_ro( 'h08, False,   0, "RDY",   "Module Ready",    "Indicates whether module is ready for processing.");
    rg_cg_busy  <- csr_reg_ro( 'h08, False,   1, "CGB",   "Codegen Busy",    "Indicates whether huffman table codegen is running.");
    rg_done     <- csr_reg_ro( 'h08, 'b0,     4, "DONE",  "Module Done",     "Indicates whether processing has finished for current image.");
    rg_error <- csr_reg_w1c(
        'h08, 'b0, 16, pw_error ? tagged Valid 1 : tagged Invalid,
        "ERR", "Module Error", "Indicates whether an error occurred processing the current image."
    );
    rg_inv_cfg <- csr_reg_w1c(
        'h08, False, 17, pw_inv_cfg ? tagged Valid True : tagged Invalid,
        "INV", "Invalid Config", "Indicates an invalid encoder configuration."
    );


    csr_reg_def('h0C, "IMSZ", "Image Size.");
    rg_imw <- csr_reg_rw('h0C, 0,  0, "IMW", "Image Width",   "");
    rg_imh <- csr_reg_rw('h0C, 0, 16, "IMH", "Image Height",  "");


    csr_reg_def('h14, "CGEN", "Huffman Codegen Config.");
    rg_cg_table_t <- csr_reg_rw( 'h14, unpack(0),    0, "TBL", "CG Table Type",     "Controls which table type to generate. 00=DC LUMA, 01=DC CHROMA, 10=AC LUMA, 11=AC CHROMA.");
    rg_cg_trigger <- csr_reg_w1s('h14, False,       31, "TRG", "Codegen Trigger",   "Writing 1 triggers huffman code generation from stored tables.");


    csr_reg_def('h30, "PERF0", "Performance Counter Cycles.");
    rg_perf_cycles <- csr_reg_ro('h30, 0, 0, "CYC", "Cycle Counter", "Number of cycles in running state since last processing start.");


    csr_reg_def('h34, "PERF1", "Performance Counter Pixels.");
    rg_perf_pixels <- csr_reg_ro('h34, 0, 0, "PIX", "Pixel Counter", "Number of pixels processed since last processing start.");


    csr_reg_def('h38, "PERF2", "Performance Counter Bytes.");
    rg_perf_byteso <- csr_reg_ro('h38, 0, 0, "BYTEO", "Out Byte Counter", "Number of encoded bytes produced since last processing start.");

    // csr_reg_def('h3C, "PERF3", "Performance Counter Cycles.");

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

    method perf_rst         = action rg_perf_cycles <= 0; rg_perf_pixels <= 0; rg_perf_byteso <= 0; endaction;

    method table_sts(r, c)  = action rg_ready <= r; rg_cg_busy <= c;    endaction;
    method error            = pw_error.send;
    method invalid_cfg      = pw_inv_cfg.send;
    method finish           = action rg_done        <= 1;               endaction;
    method clear_cg_trig    = action rg_cg_trigger  <= False;           endaction;

    interface start         = reg_to_read_only(rg_start);
    interface img_width     = reg_to_read_only(rg_imw);
    interface img_height    = reg_to_read_only(rg_imh);
    interface codegen_trig  = reg_to_read_only(rg_cg_trigger);
    interface codegen_type  = reg_to_read_only(rg_cg_table_t);

    interface perf_cycles   = reg_to_perfc(rg_perf_cycles);
    interface perf_pixels   = reg_to_perfc(rg_perf_pixels);
    interface perf_byteso   = reg_to_perfc(rg_perf_byteso);

    interface table_write   = toGet(f_fn_table_write);

endmodule

endpackage
