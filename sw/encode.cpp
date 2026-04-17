#include <iostream>
#include <fstream>
#include <cstring>
#include <cstdint>
#include <vector>
#include <cmath>
#include <algorithm>
#include <ranges>
#include <cassert>
#include <chrono>
#include <filesystem>

#include "bmp.hpp"
#include "ppm.hpp"
#include "jpeg_encode.hpp"
#include "jpeghuffman.hpp"

#include "util.hpp"
#include "jpeg_encode.hpp"

int main(int argc, char** argv) {

    using namespace std::chrono;

    bmp_image img("../assets/sample_192x192.bmp");
    // bmp_image img("../192x192.bmp");
    bool loaded = img.load();

    //convert pixels so that data starts with origin (top left)
    auto reordered_pixels = ppm::bmp2ppm_pixels(img);
    auto img_ycbcr = reordered_pixels | std::views::transform(rgb2ycbcr);

    auto subsampling_mode = subsampling_t::YCBCR_422;

    jpegencode::jpeg_params_t params {
        .width                          = img.width(),
        .height                         = img.height(),
        .quality                        = 50,
        .output_filename                = "JPEGJPEJGPEJG",
        .subsampling_mode               = subsampling_mode,
        .use_predefined_huffman_tables  = true,
        .huffman_tables                 = nullptr 
    };

    std::cout << "Encoding jpeg" << std::endl;
    auto start = std::chrono::steady_clock::now();
    auto bytes = jpegencode::encode_jpeg(img_ycbcr, params);
    auto end = std::chrono::steady_clock::now();
    auto duration = duration_cast<milliseconds>(end-start);
    std::cout << std::format("took {}", duration) << std::endl;
    std::cout << std::format("Wrote {} bytes", bytes) << std::endl;

    ppm::write_to_file("big_ppm.ppm", ppm::bmp2ppm_pixels(img), img.width(), img.height(), true);

    // std::cout << std::filesystem::file_size("JPEGJPEJGPEJG.jpg") << std::endl;

    return 0;
}