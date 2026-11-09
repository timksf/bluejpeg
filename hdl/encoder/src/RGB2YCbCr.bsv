package RGB2YCbCr;

import GetPut :: *;
import ClientServer :: *;
import FIFO :: *;
import SpecialFIFOs :: *;
import UniqueWrappers :: *;
import BlueAXI :: *;
import BlueCSRAXI4LiteAdapter :: *;
import BlueCSRCore :: *;

import Types :: *;
import PrintUtil :: *;
import Util :: *;

/*
    This file contains the implementation of the rgb to ycbcr colorspace conversion.
    The module is supposed to be standalone and not part of the JPEG pipeline, so it has its own AXI interfaces.
*/

//interface for bus-placed module
interface RGB2YCbCr_ifc#(numeric type dw);
    //data interface is stream based
    (*prefix="S_AXIS"*)
    interface AXI4_Stream_Rd_Fab#(dw, 0) fab_data_rd;
    (*prefix="M_AXIS"*)
    interface AXI4_Stream_Wr_Fab#(dw, 0) fab_data_wr;

    //config interface
    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) fab_config_rd;
    (* prefix="S_AXI_cfg" *)
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) fab_config_wr;

    (* always_ready, result="irq" *)
    method Bool irq;
endinterface

//internal interface to the configuration registers
interface RGB2YCbCrCfg_ifc#(numeric type coeff_width);
    method Action start_accepted();
    method Action finish();
    method Action pixel_ctr(UInt#(32) value);

    interface ReadOnly#(Bool) start;
    interface ReadOnly#(RGB2YCbCrParams_t#(coeff_width)) coeffs;
endinterface

//converter interface for module placed into pixel stream
interface RGB2YCbCrConv_ifc;
    interface Server#(RGB_t, YCbCr_t) data;
endinterface

typedef struct {
    //y' = a * (R-G) + b*G + c*(B-G)
    //Cb = d * (B-Y')
    //Cr = e * (R-Y')
    Int#(w) a;      //CA
    Int#(w) log2_b; //new
    Int#(w) c;      //CB
    Int#(w) d;      //CD
    Int#(w) e;      //CC
} RGB2YCbCrParams_t#(numeric type w) deriving(Bits, Eq, FShow);

module [BlueCSRCtx_t#(32, 32)] rgb2ycbcr_csrs(RGB2YCbCrCfg_ifc#(coeff_width))
    provisos(
        Add#(coeff_width, coeff_pad__, 32)
    );

    ReadOnly#(Bool)      rg_start;
    ReadOnly#(Bool)      rg_finished;
    ReadOnly#(UInt#(32)) rg_pixel_ctr;

    ReadOnly#(Int#(coeff_width)) rg_coeff_a;
    ReadOnly#(Int#(coeff_width)) rg_coeff_log2b;
    ReadOnly#(Int#(coeff_width)) rg_coeff_c;
    ReadOnly#(Int#(coeff_width)) rg_coeff_d;
    ReadOnly#(Int#(coeff_width)) rg_coeff_e;

    PulseWire                pw_clear_start     <- mkPulseWire;
    Wire#(Maybe#(Bool))      w_finished_update  <- mkDWire(tagged Invalid);
    Wire#(Maybe#(UInt#(32))) w_pixel_ctr_update <- mkDWire(tagged Invalid);
    Wire#(Bool)              w_irq_done_event   <- mkDWire(False);

    csr_regmap_def("RGB2YCbCr", "RGB to YCbCr converter register file.");

    csr_reg_def('h00, "CTRL",    "Control Register.");
    rg_start <- csr_reg_hu(
        'h00, False, 0,
        pw_clear_start ? tagged Valid False : tagged Invalid,
        "START", "Module Start", "Writing a 1 starts conversion. Hardware clears the field after accepting the command."
    );

    csr_reg_def('h04, "STS",     "Status Register.");
    rg_finished <- csr_reg_ho('h04, False, 0, w_finished_update, "DONE", "Module Finished", "Indicates that the input frame has been converted.");

    csr_reg_def('h08, "PERF",    "Pixel Counter Register.");
    rg_pixel_ctr <- csr_reg_ho('h08, 0, 0, w_pixel_ctr_update, "PIX", "Pixel Counter", "Number of converted pixels in the current frame.");

    csr_reg_def('h0C, "COEFFA",  "Luma red coefficient register.");
    rg_coeff_a     <- csr_reg_wo('h0C, 0, 0, "A",     "Coefficient A",     "Scaled luma red coefficient.");

    csr_reg_def('h10, "COEFFB",  "Coefficient scale register.");
    rg_coeff_log2b <- csr_reg_wo('h10, 0, 0, "LOG2B", "Coefficient Scale", "Base-2 logarithm of the coefficient scale.");

    csr_reg_def('h14, "COEFFC",  "Luma blue coefficient register.");
    rg_coeff_c     <- csr_reg_wo('h14, 0, 0, "C",     "Coefficient C",     "Scaled luma blue coefficient.");

    csr_reg_def('h18, "COEFFD",  "Cb coefficient register.");
    rg_coeff_d     <- csr_reg_wo('h18, 0, 0, "D",     "Coefficient D",     "Scaled Cb coefficient.");

    csr_reg_def('h1C, "COEFFE",  "Cr coefficient register.");
    rg_coeff_e     <- csr_reg_wo('h1C, 0, 0, "E",     "Coefficient E",     "Scaled Cr coefficient.");

    csr_reg_def('h20, "IRQ_STS", "Interrupt Status Register.");
    csr_reg_def('h24, "IRQ_EN",  "Interrupt Enable Register.");
    csr_irq(
        'h20, 'h24, 0, 0, w_irq_done_event,
        "DONE_IRQ", "Conversion Complete", "A completed conversion is pending acknowledgement."
    );

    method Action start_accepted();
        pw_clear_start.send;
        w_finished_update <= tagged Valid False;
        w_pixel_ctr_update <= tagged Valid 0;
    endmethod

    method Action finish();
        w_finished_update <= tagged Valid True;
        w_irq_done_event <= True;
    endmethod

    method pixel_ctr(value) = w_pixel_ctr_update._write(tagged Valid value);

    interface start = rg_start;

    interface ReadOnly coeffs;
        method _read = RGB2YCbCrParams_t {
            a: rg_coeff_a,
            log2_b: rg_coeff_log2b,
            c: rg_coeff_c,
            d: rg_coeff_d,
            e: rg_coeff_e
        };
    endinterface

endmodule

module [Module] mkRGB2YCbCrTop(RGB2YCbCr_ifc#(dw))
    provisos(
        Add#(0, dw, 24), //fix to 24 for now (3x8bit for RGB_t), could adjust for higher resolution RGB_t later on
        NumAlias#(coeff_w, 17) //TODO parametrize
    );
    //data interface AXI4 Stream
    AXI4_Stream_Rd#(dw, 0) i_axis_rd <- mkAXI4_Stream_Rd(1); //buffer size param
    AXI4_Stream_Wr#(dw, 0) i_axis_wr <- mkAXI4_Stream_Wr(1); //buffer size param

    //config interface AXI4 Lite
    BlueCSRAccess_ifc#(32, 32, 1, RGB2YCbCrCfg_ifc#(coeff_w)) i_csrs <- create_blue_csr(rgb2ycbcr_csrs, False);
    let i_axi_csrs <- mkBlueCSRAXI4LiteAdapter(i_csrs.external, 1, 1);

    //actual colorspace converter
    NumProxy_t#(coeff_w) coeff_width = ?;
    RGB2YCbCrConv_ifc    i_conv      <- mkRGB2YCbCrConv(coeff_width, i_csrs.internal.coeffs);

    Reg#(UInt#(32)) rg_in_conv[2] <- mkCRegU(2);
    Reg#(UInt#(32)) rg_ctr        <- mkRegU;
    Reg#(Bool)      rg_last       <- mkRegU;
    Reg#(Bool)      rg_running    <- mkReg(False);

    rule r_init (i_csrs.internal.start() && !rg_running);
        rg_in_conv[0] <= 0;
        rg_ctr <= 0;
        rg_running <= True;
        rg_last <= False;
        i_csrs.internal.start_accepted();
    endrule

    //from the AXI stream to the converter module
    rule r_fwd_in (rg_running);
        //we expect each packet to contain an RGB_t pixel
        let pkg <- i_axis_rd.pkg.get();
        if(pkg.keep == 'b111) begin //discard packets with any invalid value
            i_conv.data.request.put(unpack(pkg.data));
            rg_in_conv[0] <= rg_in_conv[0] + 1;
            rg_last <= pkg.last;
        end
    endrule

    rule r_fwd_out (rg_running);
        let ycbcr   <- i_conv.data.response.get();
        let new_ctr = rg_ctr + 1;
        i_csrs.internal.pixel_ctr(new_ctr);
        rg_ctr <= new_ctr;
        rg_in_conv[1] <= rg_in_conv[1] - 1;
        Bool last = False;
        if(rg_last && rg_in_conv[1] == 1) begin
            i_csrs.internal.finish();
            rg_running <= False;
            last = True;
        end
        i_axis_wr.pkg.put(AXI4_Stream_Pkg {
            data: pack(ycbcr),
            user: ?,
            keep: unpack(-1), //keep all
            dest: ?,
            id: 0,
            last: last
        });
    endrule

    interface fab_data_rd = i_axis_rd.fab;
    interface fab_data_wr = i_axis_wr.fab;
    interface fab_config_rd = i_axi_csrs.s_rd;
    interface fab_config_wr = i_axi_csrs.s_wr;
    method irq = i_axi_csrs.irqs[0];
endmodule

module mkRGB2YCbCrConv#(NumProxy_t#(w) _, RGB2YCbCrParams_t#(w) params)(RGB2YCbCrConv_ifc)
    provisos(
        Add#(a__, 8, w), //w > 8
        Add#(w, 8, w1) //w1 = w + 8 for multiplication
    );

    function print_fmt = print_mod_pre_color_t_f;

    FIFO#(RGB_t)   f_rgb   <- mkFIFO;
    FIFO#(YCbCr_t) f_ycbcr <- mkFIFO;

    //skid buffers between stages
    FIFO#(Int#(w1))                             f_stage_y <- mkPipelineFIFO;
    FIFO#(Tuple3#(Int#(w), Int#(w1), Int#(w1))) f_final   <- mkPipelineFIFO;

    /*
        Original conversion factors are scaled by a power of two.
        The conversion follows the nested approach to avoid the many multiplications required in the maxtrix-based approach:

        Y' = a * (R-G) + b*G + c*(B-G)
        Cb = d * (B-Y')
        Cr = e * (R-Y')

        For JPEG the coefficients are:
        a = 0.299, b = 1, c = 0.114, d = 0.5643, e = 0.7133

        To avoid floating or fixed point operations, we scale these coefficients with some power of two to be able to use integers.
        With an error threshold of 1/512, the resulting coefficients are:

        a = 9798, b = 32768, c = 3736, d = 18492, e = 23372

        To obtain the same final results as with floating point operations, the results have to be scaled back by the scaling factor.
        It's important to scale back Y' used in Cr and Cb calculations before these calculations are performed.
    */

    rule r_stage_y;
        let rgb = f_rgb.first;
        Int#(w1) r          = unpack(pack(zeroExtend(rgb.r)));
        Int#(w1) g          = unpack(pack(zeroExtend(rgb.g)));
        Int#(w1) b          = unpack(pack(zeroExtend(rgb.b)));
        Int#(w1) log2_b_ext = extend(params.log2_b);
        Int#(w1) y_sc       = extend(params.a) * (r - g) + (g << log2_b_ext) + extend(params.c) * (b - g);
        // print_fmt($format("RGB_t input: ") + fshow(rgb), RED);
        // print_fmt($format("Params input: ") + fshow(params), RED);
        // print_fmt($format("Y_sc: %0d", y_sc), RED);
        // print_fmt($format("e: %0d", e), RED);
        f_stage_y.enq(y_sc);
    endrule

    rule r_stage_cb_cr;
        let rgb  = f_rgb.first;
        let y_sc = f_stage_y.first;
        Int#(w1) r       = unpack(pack(zeroExtend(rgb.r)));
        Int#(w1) b       = unpack(pack(zeroExtend(rgb.b)));
        Int#(w)  y_final = truncate(y_sc >> params.log2_b);
        Int#(w1) cb_sc   = extend(params.d) * (b - extend(y_final));
        Int#(w1) cr_sc   = extend(params.e) * (r - extend(y_final));
        f_stage_y.deq;
        f_rgb.deq;
        f_final.enq(tuple3(y_final, cb_sc, cr_sc));
    endrule

    rule r_stage_final;
        match {.y_final, .cb_sc, .cr_sc} = f_final.first;
        Int#(w1) log2_b_ext = extend(params.log2_b);
        Int#(w1) cb_final   = (cb_sc >> log2_b_ext) + 128;
        Int#(w1) cr_final   = (cr_sc >> log2_b_ext) + 128;

        UInt#(8) y  = unpack(pack(truncate(y_final)));
        UInt#(8) cb = unpack(pack(truncate(cb_final)));
        UInt#(8) cr = unpack(pack(truncate(cr_final)));

        f_ycbcr.enq(YCbCr_t { y : y, cb : cb, cr : cr});
        f_final.deq;
    endrule

    interface data = toGPServer(f_rgb, f_ycbcr);

endmodule

endpackage
