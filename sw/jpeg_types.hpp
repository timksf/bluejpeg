#ifndef __JPEG_TYPES__
#define __JPEG_TYPES__

#include <cstdlib>
#include <cstdint>
#include <utility>
#include <bitset>

enum class JPEGCoeffCategory: uint8_t {
    DC = 0,
    AC = 1
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