#include <iostream>
#include <fstream>
#include <cstdint>
#include <vector>
#include <ranges>
#include <chrono>
#include <cstring>

#include "bmp.hpp"
#include "ppm.hpp"
#include "util.hpp"
#include "jpeg_encode.hpp"
#include "fixed_point_pipeline.hpp"

static void print_usage(const char *prog) {
    std::cerr << "Usage: " << prog << " <input.bmp> <output_name> <subsampling: 444|422|420>" << std::endl;
    std::cerr << "  bits=16, dct_scale=12, q_scale=12 (matching default HW instantiation)" << std::endl;
}

//HW parameters - change 'bits' to compare different data path widths
constexpr int bits = 16;
constexpr int dct_scale = 12;
constexpr int q_scale = 12;

int main(int argc, char **argv) {
    using namespace std::chrono;
    using coeff = jpeg_fixedpoint::coeff_t<bits>;

    if(argc < 4) {
        print_usage(argv[0]);
        return 1;
    }

    const char *input_file = argv[1];
    const char *output_name = argv[2];
    const char *ss_str = argv[3];

    subsampling_t subsampling;
    if(std::strcmp(ss_str, "444") == 0)        subsampling = subsampling_t::YCBCR_444;
    else if(std::strcmp(ss_str, "422") == 0)   subsampling = subsampling_t::YCBCR_422;
    else if(std::strcmp(ss_str, "420") == 0)   subsampling = subsampling_t::YCBCR_420;
    else {
        std::cerr << "Invalid subsampling mode: " << ss_str << std::endl;
        return 1;
    }

    //load image
    bmp_image img(input_file);
    if(!img.load()) {
        std::cerr << "Failed to load " << input_file << std::endl;
        return 1;
    }

    auto reordered_pixels = ppm::bmp2ppm_pixels(img);
    auto img_ycbcr = reordered_pixels | std::views::transform(rgb2ycbcr);

    //copy default quantization tables, will get scaled later
    uint8_t luma_q[64], chroma_q[64];
    std::copy(std::begin(jpegencode::std_luma_quant),   std::end(jpegencode::std_luma_quant), luma_q);
    std::copy(std::begin(jpegencode::std_chroma_quant), std::end(jpegencode::std_chroma_quant), chroma_q);

    //build fixed-point pipeline callables
    auto dct_fn     = fixedpoint_pipeline::make_fixed_dct<dct_scale, bits>();
    auto quant_fn   = fixedpoint_pipeline::make_fixed_quantize<q_scale, bits>();
    auto reorder_fn = fixedpoint_pipeline::make_zigzag<bits>();

    jpegencode::jpeg_params_t params {
        .width                          = img.width(),
        .height                         = img.height(),
        .quality                        = 50, //not used when tables supplied explicitly
        .output_filename                = output_name,
        .subsampling_mode               = subsampling,
        .use_predefined_huffman_tables  = true,
        .huffman_tables                 = nullptr,
        .interleaved                    = true
    };

    std::cout << "Bit-accurate encoding: " << input_file
              << " (" << img.width() << "x" << img.height() << ")"
              << " subsampling=" << ss_str
              << " bits=" << bits
              << " dct_scale=" << dct_scale
              << " q_scale=" << q_scale
              << std::endl;

    auto start = steady_clock::now();
    auto bytes = jpegencode::encode_jpeg<coeff>(
        img_ycbcr,
        params,
        std::span<uint8_t, 64>{ luma_q },
        std::span<uint8_t, 64>{ chroma_q },
        dct_fn,
        quant_fn,
        reorder_fn
    );
    auto end = steady_clock::now();

    std::cout << "Wrote " << bytes << " bytes in "
              << duration_cast<milliseconds>(end - start) << std::endl;

    return 0;
}
