package RGB2YCbCr;

import GetPut :: *;
import ClientServer :: *;
import FIFO :: *;
import SpecialFIFOs :: *;
import UniqueWrappers :: *;

import BlueAXI :: *;

import Types :: *;
import PrintUtil :: *;
import Util :: *;

/*
    This file contains the implementation of the rgb to ycbcr colorspace conversion.
    The module is supposed to be standalone and not part of the JPEG pipeline, so it has its own AXI interfaces.
*/

Integer cfg_start_offs          = 'h00;
Integer cfg_finished_offs       = 'h04;
Integer cfg_pixel_ctr_offs      = 'h08;
Integer cfg_coeff_a_offs        = 'h0C;
Integer cfg_coeff_log2b_offs    = 'h10;
Integer cfg_coeff_c_offs        = 'h14;
Integer cfg_coeff_d_offs        = 'h18;
Integer cfg_coeff_e_offs        = 'h1C;

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
endinterface

//internal interface to the configuration registers
interface RGB2YCbCrCfg_ifc#(numeric type coeff_width);
    interface Reg#(Bool) start;
    interface WriteOnly#(Bool) finished;
    interface WriteOnly#(UInt#(32)) pixel_ctr;
    interface ReadOnly#(RGB2YCbCr_params#(coeff_width)) coeffs;
endinterface

//converter interface for module placed into pixel stream
interface RGB2YCbCrConv_ifc;
    interface Server#(RGB_t, YCbCr_t) data;
endinterface

typedef struct {
    // Y' = a * (R-G) + b*G + c*(B-G)
    // Cb = d * (B-Y')
    // Cr = e * (R-Y')
    Int#(w) a; //CA
    Int#(w) log2_b; //new
    Int#(w) c; //CB
    Int#(w) d; //CD
    Int#(w) e; //CC
} RGB2YCbCr_params#(numeric type w) deriving(FShow, Eq, Bits);

module [ConfigCtx#(32, 32)] rgb2ycbcrConfig(RGB2YCbCrCfg_ifc#(coeff_width));

    Reg#(Bool) rStart <- mkRegU;
    Reg#(Bool) rFinished <- mkRegU;
    Reg#(UInt#(32)) rPixelCtr <- mkRegU;

    Reg#(Int#(coeff_width)) rCoeff_A <- mkRegU;
    Reg#(Int#(coeff_width)) rCoeff_Log2B <- mkRegU;
    Reg#(Int#(coeff_width)) rCoeff_C <- mkRegU;
    Reg#(Int#(coeff_width)) rCoeff_D <- mkRegU;
    Reg#(Int#(coeff_width)) rCoeff_E <- mkRegU;

    //the access policy is as seen from AXI, so a write-only register can only be written from AXI
    addRegWO(cfg_start_offs, rStart); //this should be clear-on-read over the device ifc for optimal convenience

    addRegRO(cfg_finished_offs, rFinished);
    addRegRO(cfg_pixel_ctr_offs, rPixelCtr);

    addRegWO(cfg_coeff_a_offs, rCoeff_A);
    addRegWO(cfg_coeff_log2b_offs, rCoeff_Log2B);
    addRegWO(cfg_coeff_c_offs, rCoeff_C);
    addRegWO(cfg_coeff_d_offs, rCoeff_D);
    addRegWO(cfg_coeff_e_offs, rCoeff_E);

    //the access policy here is for the device-facing interface
    interface start = (rStart);

    interface finished = regToWriteOnly(rFinished);
    interface pixel_ctr = regToWriteOnly(rPixelCtr);

    interface ReadOnly coeffs;
        method _read = RGB2YCbCr_params {
            a: rCoeff_A,
            log2_b: rCoeff_Log2B,
            c: rCoeff_C,
            d: rCoeff_D,
            e: rCoeff_E
        };
    endinterface

endmodule

module [Module] mkRGB2YCbCrTop(RGB2YCbCr_ifc#(dw))
    provisos(
        Add#(0, dw, 24), //fix to 24 for now (3x8bit for RGB_t), could adjust for higher resolution RGB_t later on
        NumAlias#(coeff_w, 17) //TODO parametrize
    );
    //data interface AXI4 Stream
    AXI4_Stream_Rd#(dw, 0) axis_rd <- mkAXI4_Stream_Rd(1); //buffer size param
    AXI4_Stream_Wr#(dw, 0) axis_wr <- mkAXI4_Stream_Wr(1); //buffer size param

    //config interface AXI4 Lite 
    IntExtConfig_ifc#(32, 32, RGB2YCbCrCfg_ifc#(coeff_w)) config_ <- axi4LiteConfigFromContext(rgb2ycbcrConfig);

    //actual colorspace converter
    NumProxy#(coeff_w) coeff_width = ?;
    RGB2YCbCrConv_ifc conv <- mkRGB2YCbCrConv(coeff_width, config_.device_ifc.coeffs);

    Reg#(UInt#(32)) rInConv[2] <- mkCRegU(2);
    Reg#(UInt#(32)) rCtr <- mkRegU;
    Reg#(Bool) rLast <- mkRegU;
    Reg#(Bool) rRunning <- mkReg(False);

    rule rinit if(config_.device_ifc.start() && !rRunning);
        rInConv[0] <= 0;
        rCtr <= 0;
        rRunning <= True;
        rLast <= False;
        config_.device_ifc.pixel_ctr <= 0;
        config_.device_ifc.finished <= False;
        config_.device_ifc.start <= False;
    endrule
    
    //from the AXI stream to the converter module
    rule rfwd_in if(rRunning);
        //we expect each packet to contain an RGB_t pixel
        let pkg <- axis_rd.pkg.get();
        if(pkg.keep == 'b111) begin //discard packets with any invalid value
            conv.data.request.put(unpack(pkg.data));
            rInConv[0] <= rInConv[0] + 1;
            rLast <= pkg.last;
        end
    endrule

    rule rfwd_out if(rRunning);
    	let ycbcr <- conv.data.response.get();
        let new_ctr = rCtr + 1;
        config_.device_ifc.pixel_ctr <= new_ctr;
        rCtr <= new_ctr;
        rInConv[1] <= rInConv[1] - 1;
        Bool last = False;
        if(rLast && rInConv[1] == 1) begin
            config_.device_ifc.finished <= True;
            rRunning <= False;
            last = True;
        end
        axis_wr.pkg.put(AXI4_Stream_Pkg {
            data: pack(ycbcr),
            user: ?,
            keep: unpack(-1), //keep all
            dest: ?,
            last: last
        });
    endrule

    interface fab_data_rd = axis_rd.fab;
    interface fab_data_wr = axis_wr.fab;
    interface fab_config_rd = config_.bus_ifc.s_rd;
    interface fab_config_wr = config_.bus_ifc.s_wr;
endmodule

module mkRGB2YCbCrConv#(NumProxy#(w) _, RGB2YCbCr_params#(w) params)(RGB2YCbCrConv_ifc)
    provisos(
        Add#(a__, 8, w), //w > 8
        Add#(w, 8, w1) //w1 = w + 8 for multiplication
    );

    function print_fmt = print_mod_pre_color_t_f;

    FIFO#(RGB_t)    f_rgb   <- mkFIFO;
    FIFO#(YCbCr_t)  f_ycbcr <- mkFIFO;

    //skid buffers between stages
    FIFO#(Int#(w1)) fStageY <- mkPipelineFIFO;
    FIFO#(Tuple3#(Int#(w), Int#(w1), Int#(w1))) fFinal <- mkPipelineFIFO;

    /*
        Original conversion factors are scaled by a power of two.
        The conversion follows the nested approach to avoid the many multiplications required in the maxtrix-based approach:

        Y' = a * (R-G) + b*G + c*(B-G)
        Cb = d * (B-Y')
        Cr = e * (R-Y')

        For JPEG the coefficients are:
        a = 0.299; b = 1; c = 0.114; d = 0.5643; e = 0.7133;

        To avoid floating or fixed point operations, we scale these coefficients with some power of two to be able to use integers.
        With an error threshold of 1/512, the resulting coefficients are:

        a = 9798; b = 32768; c = 3736; d = 18492; e = 23372

        To obtain the same final results as with floating point operations, the results have to be scaled back by the scaling factor.
        It's important to scale back Y' used in Cr and Cb calculations before these calculations are performed.
    */

    rule rstage_Y;
        let rgb = f_rgb.first;
        Int#(w1) r = unpack(pack(zeroExtend(rgb.r)));
        Int#(w1) g = unpack(pack(zeroExtend(rgb.g)));
        Int#(w1) b = unpack(pack(zeroExtend(rgb.b)));
        Int#(w1) log2_b_ext = extend(params.log2_b);
        Int#(w1) y_sc = extend(params.a) * (r - g) + (g << log2_b_ext) + extend(params.c) * (b - g);
        // print_fmt($format("RGB_t input: ") + fshow(rgb), RED);
        // print_fmt($format("Params input: ") + fshow(params), RED);
        // print_fmt($format("Y_sc: %0d", y_sc), RED);
        // print_fmt($format("e: %0d", e), RED);
        fStageY.enq(y_sc);
    endrule

    rule rstage_CbCr;
        let rgb = f_rgb.first;
        let y_sc = fStageY.first;
        Int#(w1) r = unpack(pack(zeroExtend(rgb.r)));
        Int#(w1) b = unpack(pack(zeroExtend(rgb.b)));
        Int#(w) y_final = truncate(y_sc >> params.log2_b);
        Int#(w1) cb_sc = extend(params.d) * (b - extend(y_final));
        Int#(w1) cr_sc = extend(params.e) * (r - extend(y_final));
        fStageY.deq;
        f_rgb.deq;
        fFinal.enq(tuple3(y_final, cb_sc, cr_sc));
    endrule

    rule rstage_final;
        match {.y_final, .cb_sc, .cr_sc} = fFinal.first;
        Int#(w1) log2_b_ext = extend(params.log2_b);
        Int#(w1) cb_final = (cb_sc >> log2_b_ext) + 128;
        Int#(w1) cr_final = (cr_sc >> log2_b_ext) + 128;

        UInt#(8) y =  unpack(pack(truncate(y_final)));
        UInt#(8) cb = unpack(pack(truncate(cb_final)));
        UInt#(8) cr = unpack(pack(truncate(cr_final)));

        f_ycbcr.enq(YCbCr_t { y : y, cb : cb, cr : cr});
        fFinal.deq;
    endrule

    interface data = toGPServer(f_rgb, f_ycbcr);

endmodule

endpackage
