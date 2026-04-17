#include <iostream>
#include <random>
#include <algorithm>
#include <vector>
#include <ctime>

#include "util.hpp"
#include "dct.hpp"

int main() {
    using namespace dct;

    std::srand(unsigned(0)); //std::time(nullptr)

    std::vector<uint8_t> values(64);
    std::generate(values.begin(), values.end(), std::rand);

    int16_t block[64];
    int16_t dct[64];
    int16_t dct_naive[64];
    std::ranges::copy(values, std::begin(block));

    for(auto l = 0; l < 64; l++)
        block[l] -= 128;

    dct::dct2d_as_1d<int16_t, 8>(block, dct, dct::dct1d_aan_unscaled<int16_t, float>);
    dct2d_naive<int16_t, 8>(block, dct_naive);

    std::cout << "DCT results: " << std::endl;
    print_range_formatted("{:d}", dct);
    std::cout << std::endl;

    std::cout << "Naive DCT results: " << std::endl;
    print_range_formatted("{:d}", dct_naive);
    std::cout << std::endl;


    return 0;
}