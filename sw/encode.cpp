#include <iostream>
#include <cstring>
#include <cstdint>
#include <vector>
#include <ranges>
#include <chrono>

#include "bmp.hpp"
#include "ppm.hpp"
#include "util.hpp"
#include "jpeg_encode.hpp"

static void print_usage(const char *prog) {
    std::cerr << "Usage: " << prog << " <input.bmp> <output_name> <subsampling: 444|422|420> [quality: 1-100] [--no-huffman-tables] [--non-interleaved]" << std::endl;
    std::cerr << "  quality defaults to 50. Uses floating-point AAN DCT with integer-division quantization." << std::endl;
    std::cerr << "  --no-huffman-tables: derive Huffman tables from image statistics instead of JPEG standard tables." << std::endl;
    std::cerr << "  --non-interleaved:   write separate scan per component instead of a single interleaved scan." << std::endl;
}

int main(int argc, char** argv) {
    using namespace std::chrono;

    if(argc < 4) {
        print_usage(argv[0]);
        return 1;
    }

    const char *input_file = argv[1];
    const char *output_name = argv[2];
    const char *ss_str = argv[3];

    subsampling_t subsampling;
    if(std::strcmp(ss_str, "444") == 0)         subsampling = subsampling_t::YCBCR_444;
    else if(std::strcmp(ss_str, "422") == 0)    subsampling = subsampling_t::YCBCR_422;
    else if(std::strcmp(ss_str, "420") == 0)    subsampling = subsampling_t::YCBCR_420;
    else {
        std::cerr << "Invalid subsampling mode: " << ss_str << std::endl;
        return 1;
    }

    int quality = 50;
    bool use_default_huffman = true;
    bool interleaved = true;

    for (int i = 4; i < argc; ++i) {
        if(std::strcmp(argv[i], "--no-huffman-tables") == 0) {
            use_default_huffman = false;
        } else if(std::strcmp(argv[i], "--non-interleaved") == 0) {
            interleaved = false;
        } else {
            char *end;
            long q = std::strtol(argv[i], &end, 10);
            if(*end != '\0' || q < 1 || q > 100) {
                std::cerr << "Invalid argument: " << argv[i] << std::endl;
                print_usage(argv[0]);
                return 1;
            }
            quality = static_cast<int>(q);
        }
    }

    //load image
    bmp_image img(input_file);
    if(!img.load()) {
        std::cerr << "Failed to load " << input_file << std::endl;
        return 1;
    }

    auto reordered_pixels = ppm::bmp2ppm_pixels(img);
    auto img_ycbcr = reordered_pixels | std::views::transform(rgb2ycbcr);

    jpegencode::jpeg_params_t params {
        .width                          = img.width(),
        .height                         = img.height(),
        .quality                        = quality,
        .output_filename                = output_name,
        .subsampling_mode               = subsampling,
        .use_predefined_huffman_tables  = use_default_huffman,
        .huffman_tables                 = nullptr,
        .interleaved                    = interleaved
    };

    std::cout   << "Float encoding: " << input_file
                << " (" << img.width() << "x" << img.height() << ")"
                << " subsampling=" << ss_str
                << " quality=" << quality
                << " huffman=" << (use_default_huffman ? "default" : "derived")
                << " interleaved=" << (interleaved ? "yes" : "no")
                << std::endl;

    auto start = steady_clock::now();
    auto bytes = jpegencode::encode_jpeg(img_ycbcr, params);
    auto end = steady_clock::now();

    std::cout << "Wrote " << bytes << " bytes in "
              << duration_cast<milliseconds>(end - start) << std::endl;

    return 0;
}