#include <iostream>
#include <fstream>
#include <cstring>
#include <cstdint>
#include <vector>
#include <cmath>
#include <algorithm>
#include <iomanip>
#include <ranges>
#include <functional>

#include "util.hpp"
#include "ppm.hpp"
#include "bmp.hpp"
#include "jpeghuffman.hpp"
#include "jpeg_encode.hpp"
#include "dct.hpp"

template<typename t>
void print_arr2d(t *arr, int w, int h){
    std::cout << "  [array<" << w << "," << h << ">\n";
    for(auto i = 0; i < w*h; i++){
        if(i%w == 0) std::cout << "\t";
        std::cout << (int)arr[i] << ", ";
        if(i > 0 && ((i+1) % w == 0)) std::cout << std::endl;
    }
    std::cout << "  ]";
}

int main(int argc, char** argv) {
    namespace rng = std::ranges;
    using namespace dct;
    using namespace jpegencode;

    bmp_image img("../192x192.bmp");
    bool loaded = img.load();
    auto reordered_pixels = ppm::bmp2ppm_pixels(img);
    auto img_ycbcr = reordered_pixels | std::views::transform(rgb2ycbcr);

    std::vector<uint8_t> Y;
    rng::copy(img_ycbcr | std::views::transform([](const ycbcr_t &e){return e.y;}), std::back_inserter(Y));

    int16_t block[64] = { 0 };
    int16_t dct_naive[64] = { 0 };
    int16_t dct_fast[64] = { 0 };
    int16_t dct_test[64] = { 0 };
    auto cosine = cosine_lookup<8>;

    get_block8x8(Y, block, 0, 0, img.width(), img.height());

    dct2d_naive<int16_t, 8>(block, dct_naive);
    dct2d_fast<int16_t, 8>(block, dct_fast, cosine);
    dct2d_as_1d<int16_t, 8>(block, dct_test, dct1d_aan_unscaled<int16_t, float>); //this has more rounding errors

    // std::cout << std::format("block:") << std::endl;
    // print_range_2d_formatted("{:d}", std::span{ block }, 8, 8);

    print_range_2d_formatted("{:d}", std::span{ dct_naive }, 8, 8);

    auto close = [](auto a, auto b){ return std::fabs(a-b) < 1e-1; };

    auto calc_diff = []<rng::input_range InRange>(InRange &&r1, InRange &&r2){
        float diff = 0.f;
        auto upd_diff = [&diff](const auto &p) { diff += std::fabs(p.first - p.second); };
        rng::for_each(rng::views::zip(r1, r2), upd_diff);
        return diff;
    };
    
    float diff_fast = calc_diff(dct_naive, dct_fast);
    float diff_as1d = calc_diff(dct_naive, dct_test);

    std::cout << std::endl;
    std::cout << "Comparison with naive implementation:" << std::endl;
    std::cout << std::format("FAST: {:.6f}", diff_fast) << std::endl;
    std::cout << std::format("AS_1D: {:.6f}", diff_as1d) << std::endl;

    // int16_t row[] = {0, 1, 2, 3, 3, 3, 2, 0};
    // int16_t rowf[8] = { 0 };

    // dct1d_aan<int16_t, float>(row, rowf, true);
    // std::cout << "AAN: ";
    // // print_range_formatted("{:.4f}", rowf);
    // std::cout << std::endl << "Naive: ";
    // dct1d<int16_t, 8>(row, rowf);
    // print_range_formatted("{:.4f}", rowf);

    return EXIT_SUCCESS;
}