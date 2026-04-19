#ifndef __JPEG_TYPES__
#define __JPEG_TYPES__

#include <cstdlib>
#include <cstdint>
#include <utility>
#include <bitset>
#include <span>
#include <concepts>

enum class JPEGCoeffCategory: uint8_t {
    DC = 0,
    AC = 1
};

/*
    Concepts for generic JPEG block processing pipeline.
    These constrain the callables that can be injected into process_channel / encode_jpeg.
*/

// 2D DCT: takes input block and writes frequency coefficients to output block
template<typename F>
concept dct_2d_fn = requires(F f, std::span<int16_t, 64> in, std::span<int16_t, 64> out) {
    { f(in, out) } -> std::same_as<void>;
};

// Block quantization: modifies coefficients in-place (captures table internally)
template<typename F>
concept quantize_block_fn = requires(F f, std::span<int16_t, 64> block) {
    { f(block) } -> std::same_as<void>;
};

// Block reordering (zigzag): reads from input span, writes reordered to output span
template<typename F>
concept reorder_block_fn = requires(F f, std::span<int16_t, 64> in, std::span<int16_t, 64> out) {
    { f(in, out) } -> std::same_as<void>;
};

constexpr size_t MAX_CODE_LEN = 32;
using codeword_t = std::pair<std::bitset<MAX_CODE_LEN>, size_t>;

enum class subsampling_t {
    YCBCR_444, //no subsampling
    YCBCR_422, //half horizontal subsampling 
    YCBCR_420, //half vertical and horizontal subsampling
};

//zigzag scan order, needed both in writer and encoder
static size_t zigzag[64] = { 0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63 };

#endif //__JPEG_TYPES__