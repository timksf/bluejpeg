#include <cstdint>
#include <cmath>
#include <algorithm>
#include <iostream>

struct rgb_t {
    uint8_t r, g, b;
};

struct ycbcr_t {
    uint8_t y, cb, cr;
};

extern "C" {
    uint32_t rgb2ycbcr_ref(uint8_t r, uint8_t g, uint8_t b) {
        rgb_t rgb {r, g, b};
        float M[3][3] = {
            {0.299, 0.587, 0.114 },
            {-0.168736, -0.331264, 0.5},
            {0.5, -0.418688, -0.081312}
        };
        float y, cb, cr;
        y  = M[0][0] * rgb.r + M[0][1] * rgb.g + M[0][2] * rgb.b;
        cb = M[1][0] * rgb.r + M[1][1] * rgb.g + M[1][2] * rgb.b + 128;
        cr = M[2][0] * rgb.r + M[2][1] * rgb.g + M[2][2] * rgb.b + 128;
        ycbcr_t ycbcr { 0 };
        ycbcr.y  = static_cast<uint8_t>(std::clamp(y, 0.0f, 255.0f));
        ycbcr.cb = static_cast<uint8_t>(std::clamp(cb, 0.0f, 255.0f));
        ycbcr.cr = static_cast<uint8_t>(std::clamp(cr, 0.0f, 255.0f));
        return ycbcr.y << 16 | ycbcr.cb << 8 | ycbcr.cr;
    }
}