#ifndef __JPEG_FIXED_POINT_HPP__
#define __JPEG_FIXED_POINT_HPP__

/*
    Bit-accurate fixed-point JPEG processing kernels.
    
    These mirror the hardware pipeline exactly:
    - scaled_mul:                BSV scaled_mul_s from Util.bsv
    - dct1d_aan_fixed:           BSV DCT1D AAN butterfly stages
    - dct2d_fixed:               Row-then-column 1D DCT (matches DCT2D_Optimized)
    - quantize_coeff_fixed:      Single-coefficient quantization with pre-scaled multiplier
    - compute_scaled_quant_table: AAN-absorbed Q-table multiplier computation (matches Quantize.bsv)
    
    All functions are parameterized by fractional bit width (template parameter).
    Used both by the standalone bit-accurate SW encoder and by BDPI reference wrappers.
*/

#include <cstdint>
#include <cmath>
#include <span>
#include <array>
#include <ranges>

namespace fixedpoint {

    //
    // Saturating 16-bit signed add — mirrors BSV satPlus(Sat_Bound, a, b).
    //
    inline int16_t sat_add(int16_t a, int16_t b) {
        int32_t sum = static_cast<int32_t>(a) + static_cast<int32_t>(b);
        if (sum > 32767) return 32767;
        if (sum < -32768) return -32768;
        return static_cast<int16_t>(sum);
    }

    //
    // Fixed-point multiply with rounding — mirrors BSV scaled_mul_s exactly.
    //   val is sign-extended to (bits + bits_frac) width, multiplied, rounded, shifted, truncated.
    //   Returns Int#(bits) = int16_t.
    //
    template<int bits_frac>
    inline int16_t scaled_mul(int32_t val, int32_t f) {
        int32_t prod = val * f;
        int32_t prod_m = prod + (1 << (bits_frac - 1));
        return static_cast<int16_t>(prod_m >> bits_frac);
    }

    //
    // AAN scaling factors s[0..7] used to absorb DCT output scaling into quantization.
    //
    inline void compute_aan_scale_factors(double s[8]) {
        s[0] = 1.0 / (2.0 * std::sqrt(2.0));
        for (int i = 1; i < 8; ++i) {
            s[i] = 1.0 / (4.0 * std::cos(i * M_PI / 16.0));
        }
    }

    //
    // 1D AAN DCT with fixed-point arithmetic — bit-exact mirror of BSV DCT1D pipeline.
    //
    // All intermediates are int16_t matching BSV Int#(bits) = Int#(16).
    // Additions use sat_add (satPlus Sat_Bound).
    // Multiplies use scaled_mul which returns int16_t (truncated from wider product).
    // Negation patterns match BSV exactly: e.g. -mul(d4, a2) not mul(-d4, a2).
    //
    template<int f_scale>
    void dct1d_aan_fixed(std::span<int16_t, 8> block, std::span<int16_t, 8> freqs) {
        constexpr int32_t a1 = static_cast<int32_t>(0.707106781 * (1 << f_scale) + 0.5);
        constexpr int32_t a2 = static_cast<int32_t>(0.541196100 * (1 << f_scale) + 0.5);
        constexpr int32_t a3 = a1;
        constexpr int32_t a4 = static_cast<int32_t>(1.306562964 * (1 << f_scale) + 0.5);
        constexpr int32_t a5 = static_cast<int32_t>(0.382683432 * (1 << f_scale) + 0.5);

        auto mul = [](int16_t val, int32_t mult) -> int16_t {
            return scaled_mul<f_scale>(static_cast<int32_t>(val), mult);
        };

        //stage 0 — matches BSV rstage0 bf_add pairs
        int16_t b0 = sat_add( block[0],  block[7]);
        int16_t b1 = sat_add( block[1],  block[6]);
        int16_t b2 = sat_add( block[2],  block[5]);
        int16_t b3 = sat_add( block[3],  block[4]);
        int16_t b4 = sat_add(static_cast<int16_t>(-block[4]), block[3]);
        int16_t b5 = sat_add(static_cast<int16_t>(-block[5]), block[2]);
        int16_t b6 = sat_add(static_cast<int16_t>(-block[6]), block[1]);
        int16_t b7 = sat_add(static_cast<int16_t>(-block[7]), block[0]);

        //stage 1 — matches BSV rstage1
        int16_t c0 = sat_add( b0,  b3);
        int16_t c1 = sat_add( b1,  b2);
        int16_t c2 = sat_add(static_cast<int16_t>(-b2), b1);
        int16_t c3 = sat_add(static_cast<int16_t>(-b3), b0);
        int16_t c4 = sat_add(static_cast<int16_t>(-b4), static_cast<int16_t>(-b5));
        int16_t c5 = sat_add( b5,  b6);
        int16_t c6 = sat_add( b6,  b7);
        int16_t c7 = b7;

        //stage 2 — matches BSV rstage2
        int16_t d0 = sat_add( c0,  c1);
        int16_t d1 = sat_add(static_cast<int16_t>(-c1), c0);
        int16_t d2 = sat_add( c2,  c3);
        int16_t d3 = c3;
        int16_t d4 = c4;
        int16_t d5 = c5;
        int16_t d6 = c6;
        int16_t d7 = c7;

        //stage 3 — matches BSV rstage4
        // BSV: helper = mul(bf_add(d[4], d[6]), a5_i)
        int16_t helper = mul(sat_add(d4, d6), a5);

        // BSV: e[4] = bf_add(-mul(d[4], a2_i), -helper)
        // Note: BSV negates AFTER mul, not before — critical for rounding
        int16_t e0 = d0;
        int16_t e1 = d1;
        int16_t e2 = mul(d2, a1);
        int16_t e3 = d3;
        int16_t e4 = sat_add(static_cast<int16_t>(-mul(d4, a2)), static_cast<int16_t>(-helper));
        int16_t e5 = mul(d5, a3);
        int16_t e6 = sat_add(mul(d6, a4), static_cast<int16_t>(-helper));
        int16_t e7 = d7;

        //stage 4 — matches BSV rstage5
        int16_t f0 = e0;
        int16_t f1 = e1;
        int16_t f2 = sat_add( e2,  e3);
        int16_t f3 = sat_add( e3, static_cast<int16_t>(-e2));
        int16_t f4 = e4;
        int16_t f5 = sat_add( e5,  e7);
        int16_t f6 = e6;
        int16_t f7 = sat_add( e7, static_cast<int16_t>(-e5));

        //stage 5 — matches BSV rstage6 + output reorder
        freqs[0] = f0;
        freqs[4] = f1;
        freqs[2] = f2;
        freqs[6] = f3;
        freqs[5] = sat_add( f4,  f7);
        freqs[1] = sat_add( f5,  f6);
        freqs[7] = sat_add(static_cast<int16_t>(-f6), f5);
        freqs[3] = sat_add( f7, static_cast<int16_t>(-f4));
    }

    //
    // 2D DCT via separable 1D transforms (row then column) — matches DCT2D_Optimized.
    // Uses int16_t temp storage matching BSV Int#(bits) pipeline FIFOs.
    //
    template<int dct_scale>
    void dct2d_fixed(std::span<int16_t, 64> block, std::span<int16_t, 64> freqs) {
        int16_t temp[64];

        //1D DCT on rows
        for (int y = 0; y < 8; ++y) {
            std::span<int16_t, 8> row_in  { &block[y * 8], 8 };
            std::span<int16_t, 8> row_out { &temp[y * 8], 8 };
            dct1d_aan_fixed<dct_scale>(row_in, row_out);
        }

        //1D DCT on columns (transpose access)
        for (int x = 0; x < 8; ++x) {
            int16_t col_in[8], col_out[8];
            for (int row = 0; row < 8; ++row) col_in[row] = temp[row * 8 + x];
            dct1d_aan_fixed<dct_scale>(std::span<int16_t, 8>{ col_in }, std::span<int16_t, 8>{ col_out });
            for (int row = 0; row < 8; ++row) freqs[row * 8 + x] = col_out[row];
        }
    }

    //
    // Single-coefficient fixed-point quantization — mirrors Quantize.bsv scaled_mul_rt with trunc=True.
    // Uses truncation toward zero (not rounding):
    //   positive products: truncate (floor toward zero)
    //   negative products: add (2^q_scale - 1) before shift (ceil toward zero)
    //
    template<int q_scale>
    inline int16_t quantize_coeff_fixed(int16_t val, int16_t scaled_mult) {
        int32_t prod = static_cast<int32_t>(val) * static_cast<int32_t>(scaled_mult);
        int32_t prod_m;
        if (prod < 0) {
            prod_m = prod + ((1 << q_scale) - 1);
        } else {
            prod_m = prod;
        }
        return static_cast<int16_t>(prod_m >> q_scale);
    }

    //
    // Pre-compute HW-equivalent scaled quantization multipliers from a raw JPEG Q-table.
    // Absorbs AAN scaling factors: mult[i] = round(2^q_scale * s[row] * s[col] / Q[i])
    // This matches the table initialization in Quantize.bsv.
    //
    template<int q_scale>
    void compute_scaled_quant_table(std::span<const uint8_t, 64> raw_q, std::array<int16_t, 64> &out_mults) {
        double s[8];
        compute_aan_scale_factors(s);
        constexpr double scale = static_cast<double>(1 << q_scale);

        for (int i = 0; i < 64; ++i) {
            int row = i / 8;
            int col = i % 8;
            double scale_factor = (scale * s[row] * s[col]) / static_cast<double>(raw_q[i]);
            out_mults[i] = static_cast<int16_t>(std::round(scale_factor));
        }
    }

} // namespace fixedpoint

#endif // __JPEG_FIXED_POINT_HPP__
