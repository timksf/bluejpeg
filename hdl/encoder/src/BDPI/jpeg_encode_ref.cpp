/*
    BDPI reference encoder: runs the full SW bit-accurate JPEG encoder
    and stores the resulting bytes into SimRAM for comparison with HW output.

    Uses dct_scale=12, q_scale=12 and a 15-bit coefficient path to match
    TestJPEGBitAccuracy's optimized BlueJPEG pipeline (8-bit samples + 7 bits).
*/

#include "jpeg_fixed_point.hpp"
#include "SimRAM.h"

#include "../../../../sw/bmp.hpp"
#include "../../../../sw/ppm.hpp"
#include "../../../../sw/util.hpp"
#include "../../../../sw/fixed_point_pipeline.hpp"
#include "../../../../sw/jpeg_encode.hpp"

#include <cstdint>
#include <fstream>
#include <iostream>
#include <span>
#include <array>
#include <vector>
#include <ranges>

static constexpr int DPW        = 15;
static constexpr int DCT_SCALE  = 12;
static constexpr int Q_SCALE    = 12;

extern "C" {

    /*
        Runs the full bit-accurate JPEG encoder on a BMP image and writes
        the resulting JPEG bytes into SimRAM.

        Parameters:
            image_path       - path to BMP input file
            subsampling_mode - 0=444, 1=422, 2=420
            ram_ptr          - SimRAM pointer (from create_SimRAM)
            start_addr       - word address in SimRAM to start writing bytes

        Returns: total number of JPEG bytes produced
    */
    uint32_t jpeg_encode_ref(
        const char* image_path,
        uint8_t subsampling_mode,
        uint64_t ram_ptr,
        uint64_t start_addr
    ) {
        // Load BMP image
        bmp_image img(image_path);
        if (!img.load()) {
            std::cerr << "[jpeg_encode_ref] Failed to load " << image_path << std::endl;
            return 0;
        }

        // Convert BMP to top-left-origin pixel order (same as CImg provides)
        auto reordered_pixels = ppm::bmp2ppm_pixels(img);
        auto img_ycbcr = reordered_pixels | std::views::transform(rgb2ycbcr);

        // Map the software reference sampling code.
        subsampling_t ss;
        switch (subsampling_mode) {
            case 0:  ss = subsampling_t::YCBCR_444; break;
            case 1:  ss = subsampling_t::YCBCR_422; break;
            case 2:  ss = subsampling_t::YCBCR_420; break;
            default: ss = subsampling_t::YCBCR_444; break;
        }

        //standard JPEG quantization tables (quality 50, no scaling)
        uint8_t luma_q[64], chroma_q[64];
        std::copy(std::begin(jpegencode::std_luma_quant),   std::end(jpegencode::std_luma_quant), luma_q);
        std::copy(std::begin(jpegencode::std_chroma_quant), std::end(jpegencode::std_chroma_quant), chroma_q);

        //The hardware uses dct_safe_arith=False: wrapping adds and truncating multiplies.
        auto dct_fn     = fixedpoint_pipeline::make_fixed_dct_optimized<DCT_SCALE, DPW>();
        auto quant_fn   = fixedpoint_pipeline::make_fixed_quantize<Q_SCALE, DPW>();
        auto reorder_fn = fixedpoint_pipeline::make_zigzag<DPW>();

        //encode to a temporary file
        std::string tmp_name = "/tmp/jpeg_encode_ref_output";

        jpegencode::jpeg_params_t params {
            .width                          = img.width(),
            .height                         = img.height(),
            .quality                        = 50,
            .output_filename                = tmp_name,
            .subsampling_mode               = ss,
            .use_predefined_huffman_tables  = true,
            .huffman_tables                 = nullptr,
            .interleaved                    = true
        };

        auto bytes_written = jpegencode::encode_jpeg(
            img_ycbcr, params,
            std::span<uint8_t, 64>{ luma_q },
            std::span<uint8_t, 64>{ chroma_q },
            dct_fn, quant_fn, reorder_fn
        );

        // Read JPEG file back and store bytes in SimRAM (one byte per word)
        std::ifstream jpeg_in(tmp_name + ".jpg", std::ios::binary);
        if (!jpeg_in) {
            std::cerr << "[jpeg_encode_ref] Failed to read back " << tmp_name << ".jpg" << std::endl;
            return 0;
        }

        SimRAM* ram = reinterpret_cast<SimRAM*>(ram_ptr);
        uint64_t addr = start_addr;
        char byte;
        while (jpeg_in.get(byte)) {
            ram->write_word(addr++, static_cast<uint8_t>(byte));
        }

        std::cout << "[jpeg_encode_ref] Encoded " << bytes_written
                  << " bytes (dct_scale=" << DCT_SCALE
                  << ", q_scale=" << Q_SCALE << ")" << std::endl;

        return static_cast<uint32_t>(bytes_written);
    }

}
