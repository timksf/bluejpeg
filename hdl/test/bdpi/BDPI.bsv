package BDPI;

//create function has to be !!ActionValue!!, otherwise it might get inlined everywhere, which is very bad
import "BDPI" function ActionValue#(UInt#(64)) create_SimRAM(UInt#(32) sz, UInt#(32) bytes_per_word);
import "BDPI" function ActionValue#(UInt#(64)) read_word_SimRAM(
    UInt#(64) ptr,
    UInt#(64) addr
);
import "BDPI" function Action write_word_SimRAM(
    UInt#(64) ptr,
    UInt#(64) addr,
    UInt#(64) data
);
import "BDPI" function Action write_strobe_SimRAM(
    UInt#(64) ptr,
    UInt#(64) addr,
    UInt#(64) data,
    UInt#(64) strobe
);
import "BDPI" function ActionValue#(UInt#(64)) read_byte_SimRAM(
    UInt#(64) ptr,
    UInt#(64) byte_addr
);
import "BDPI" function Action write_byte_SimRAM(
    UInt#(64) ptr,
    UInt#(64) byte_addr,
    UInt#(64) byte_val
);

//image loader, copies an image file into the simulation ram model
import "BDPI" function ActionValue#(UInt#(64)) create_ImageLoader(String filename);
import "BDPI" function ActionValue#(UInt#(8)) get_pixel_ImageLoader(UInt#(64) ptr);

import "BDPI" function Action write_to_mem_seq_ImageLoader(
    UInt#(64) ptr,
    UInt#(64) ram_ptr,
    UInt#(64) start_addr
);

import "BDPI" function Action write_to_mem_interleaved_ImageLoader(
    UInt#(64) ptr,
    UInt#(64) ram_ptr,
    UInt#(64) start_addr
);

import "BDPI" function Action write_to_mem_gray_packed_ImageLoader(
    UInt#(64) ptr,
    UInt#(64) ram_ptr,
    UInt#(64) start_addr
);

//image writer, copies the simulation ram model into an image file
import "BDPI" function Action mem_to_file_seq_ImageWriter(
    UInt#(64) ram_ptr,
    UInt#(32) width,
    UInt#(32) height,
    String filename,
    UInt#(64) start_addr
);

//image writer, copies the simulation ram model into an image file
import "BDPI" function Action mem_to_file_gray_ImageWriter(
    UInt#(64) ram_ptr,
    UInt#(32) width,
    UInt#(32) height,
    String filename,
    UInt#(64) start_addr
);


import "BDPI" function Action mem_to_file_interleaved_ImageWriter(
    UInt#(64) ram_ptr,
    UInt#(32) width,
    UInt#(32) height,
    String filename,
    UInt#(64) start_addr
);

import "BDPI" function Action mem_to_file_gray_packed_ImageWriter(
    UInt#(64) ram_ptr,
    UInt#(32) width,
    UInt#(32) height,
    String filename,
    UInt#(64) start_addr
);

//ImageWriterStream: from values to image file
import "BDPI" function ActionValue#(UInt#(64)) create_ImageWriterStream(
    String filename,
    UInt#(32) width,
    UInt#(32) height
);

import "BDPI" function Action put_r_ImageWriterStream(
    UInt#(64) ptr,
    UInt#(8) pixel,
    Bool incr
);

import "BDPI" function Action put_g_ImageWriterStream(
    UInt#(64) ptr,
    UInt#(8) pixel,
    Bool incr
);

import "BDPI" function Action put_b_ImageWriterStream(
    UInt#(64) ptr,
    UInt#(8) pixel,
    Bool incr
);

import "BDPI" function Bit#(32) rgb2ycbcr_ref(
    UInt#(8) r,
    UInt#(8) g,
    UInt#(8) b
);

import "BDPI" function ActionValue#(Bit#(16)) rand_i16(Int#(16) min, Int#(16) max);

//1 bit of padding to trigger array passing
import "BDPI" function ActionValue#(Bit#(65))   dct_1d_i8_ref_raw(Bit#(65) in, Bool scale);
import "BDPI" function ActionValue#(Bit#(128))  dct_1d_i16_ref(Bit#(128) in, Bool scale);

//for DU_t#(Int#(16), 8, 8) ~ which contains 1024 bits
import "BDPI" function ActionValue#(Bit#(1024)) dct_2d_i16_ref(Bit#(1024) in, Bool scale);
import "BDPI" function ActionValue#(Bit#(512))  dct_2d_i8_ref(Bit#(512) in, Bool scale);

//f_scale is the number of fractional bits of the AAN multipliers and must match the hardware under test
import "BDPI" function ActionValue#(Int#(16)) quant_ref_i16(Int#(16) val, Bit#(32) idx, Bool is_luma, Bool apply_aan, Bit#(32) f_scale);

import "BDPI" function ActionValue#(Bit#(1024)) zigzag_ref_i16(Bit#(1024) in, Bool transposed);

//full JPEG reference encoder: runs the bit-accurate SW pipeline and stores the output bytes in SimRAM
//returns the total byte count
import "BDPI" function ActionValue#(UInt#(32)) jpeg_encode_ref(
    String image_path,
    UInt#(8) subsampling_mode,
    UInt#(64) ram_ptr,
    UInt#(64) start_addr
);

endpackage