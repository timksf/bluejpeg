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
    
    All functions are parameterized by:
    - bits:      data path width (BSV Int#(bits)), controls saturation and truncation (default 16)
    - bits_frac: fractional bit width for scaled multiplication
    
    Used both by the standalone bit-accurate SW encoder and by BDPI reference wrappers.
*/

#include <cstdint>
#include <cmath>
#include <span>
#include <array>
#include <ranges>
#include <type_traits>

namespace jpeg_fixedpoint {

    //
    // Coefficient storage type: int16_t for bits <= 16, int32_t for bits <= 32.
    // Mirrors BSV Int#(bits).
    //
    template<int bits>
    using coeff_t = std::conditional_t<(bits <= 16), int16_t, int32_t>;

    //
    // Wider type for intermediate arithmetic (products, sums before truncation).
    //
    template<int bits>
    using wide_t = std::conditional_t<(bits <= 16), int32_t, int64_t>;

    //
    // Representable range for a signed bits-wide value.
    //
    template<int bits>
    inline constexpr wide_t<bits> coeff_max = (wide_t<bits>{1} << (bits - 1)) - 1;

    template<int bits>
    inline constexpr wide_t<bits> coeff_min = -(wide_t<bits>{1} << (bits - 1));

    //
    // Truncate a wider value to bits width - mirrors BSV truncate(pack(val)).
    // Masks to lower 'bits' and sign-extends from bit position (bits-1).
    //
    template<int bits>
    inline coeff_t<bits> truncate_to(wide_t<bits> val) {
        constexpr wide_t<bits> mask = (wide_t<bits>{1} << bits) - 1;
        val &= mask;
        if (val & (wide_t<bits>{1} << (bits - 1)))
            val |= ~mask;
        return static_cast<coeff_t<bits>>(val);
    }

    //
    // Negate with truncation - mirrors BSV unary minus on Int#(bits).
    // Needed because -coeff_min overflows the bits-wide range.
    //
    template<int bits = 16>
    inline coeff_t<bits> neg(coeff_t<bits> val) {
        return truncate_to<bits>(-static_cast<wide_t<bits>>(val));
    }

    //
    // Saturating signed add - mirrors BSV satPlus(Sat_Bound, a, b).
    //
    template<int bits = 16>
    inline coeff_t<bits> sat_add(coeff_t<bits> a, coeff_t<bits> b) {
        wide_t<bits> sum = static_cast<wide_t<bits>>(a) + static_cast<wide_t<bits>>(b);
        if (sum > coeff_max<bits>) return static_cast<coeff_t<bits>>(coeff_max<bits>);
        if (sum < coeff_min<bits>) return static_cast<coeff_t<bits>>(coeff_min<bits>);
        return static_cast<coeff_t<bits>>(sum);
    }

    //
    // Wrapping signed add - mirrors BSV Int#(bits) addition without satPlus.
    //
    template<int bits = 16>
    inline coeff_t<bits> wrap_add(coeff_t<bits> a, coeff_t<bits> b) {
        wide_t<bits> sum = static_cast<wide_t<bits>>(a) + static_cast<wide_t<bits>>(b);
        return truncate_to<bits>(sum);
    }

    //
    // Fixed-point multiply with rounding - mirrors BSV scaled_mul_s exactly.
    //   Multiply, add rounding bit, shift right, truncate to bits width.
    //
    template<int bits_frac, int bits = 16>
    inline coeff_t<bits> scaled_mul(wide_t<bits> val, wide_t<bits> f) {
        wide_t<bits> prod = val * f;
        wide_t<bits> prod_m = prod + (wide_t<bits>{1} << (bits_frac - 1));
        return truncate_to<bits>(prod_m >> bits_frac);
    }

    //
    // Fixed-point multiply without rounding - mirrors the optimized BSV DCT path.
    //
    template<int bits_frac, int bits = 16>
    inline coeff_t<bits> scaled_mul_trunc(wide_t<bits> val, wide_t<bits> f) {
        wide_t<bits> prod = val * f;
        return truncate_to<bits>(prod >> bits_frac);
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
    // 1D AAN DCT with fixed-point arithmetic - bit-exact mirror of BSV DCT1D pipeline.
    //
    // All intermediates are coeff_t<bits> matching BSV Int#(bits).
    // Additions use sat_add (satPlus Sat_Bound).
    // Multiplies use scaled_mul which truncates to bits width.
    // Negation uses neg<bits> for correct overflow behavior.
    //
    template<int f_scale, int bits = 16>
    void dct1d_aan_fixed(std::span<coeff_t<bits>, 8> block, std::span<coeff_t<bits>, 8> freqs) {
        using C = coeff_t<bits>;
        using W = wide_t<bits>;
        constexpr W a1 = static_cast<W>(0.707106781 * (1 << f_scale) + 0.5);
        constexpr W a2 = static_cast<W>(0.541196100 * (1 << f_scale) + 0.5);
        constexpr W a3 = a1;
        constexpr W a4 = static_cast<W>(1.306562964 * (1 << f_scale) + 0.5);
        constexpr W a5 = static_cast<W>(0.382683432 * (1 << f_scale) + 0.5);

        auto mul = [](C val, W mult) -> C {
            return scaled_mul<f_scale, bits>(static_cast<W>(val), mult);
        };

        //stage 0 - matches BSV rstage0 bf_add pairs
        C b0 = sat_add<bits>(block[0], block[7]);
        C b1 = sat_add<bits>(block[1], block[6]);
        C b2 = sat_add<bits>(block[2], block[5]);
        C b3 = sat_add<bits>(block[3], block[4]);
        C b4 = sat_add<bits>(neg<bits>(block[4]), block[3]);
        C b5 = sat_add<bits>(neg<bits>(block[5]), block[2]);
        C b6 = sat_add<bits>(neg<bits>(block[6]), block[1]);
        C b7 = sat_add<bits>(neg<bits>(block[7]), block[0]);

        //stage 1 - matches BSV rstage1
        C c0 = sat_add<bits>(b0, b3);
        C c1 = sat_add<bits>(b1, b2);
        C c2 = sat_add<bits>(neg<bits>(b2), b1);
        C c3 = sat_add<bits>(neg<bits>(b3), b0);
        C c4 = sat_add<bits>(neg<bits>(b4), neg<bits>(b5));
        C c5 = sat_add<bits>(b5, b6);
        C c6 = sat_add<bits>(b6, b7);
        C c7 = b7;

        //stage 2 - matches BSV rstage2
        C d0 = sat_add<bits>(c0, c1);
        C d1 = sat_add<bits>(neg<bits>(c1), c0);
        C d2 = sat_add<bits>(c2, c3);
        C d3 = c3;
        C d4 = c4;
        C d5 = c5;
        C d6 = c6;
        C d7 = c7;

        //stage 3 - matches BSV rstage4
        // BSV: helper = mul(bf_add(d[4], d[6]), a5_i)
        C helper = mul(sat_add<bits>(d4, d6), a5);

        // BSV: e[4] = bf_add(-mul(d[4], a2_i), -helper)
        // Note: BSV negates AFTER mul, not before - critical for rounding
        C e0 = d0;
        C e1 = d1;
        C e2 = mul(d2, a1);
        C e3 = d3;
        C e4 = sat_add<bits>(neg<bits>(mul(d4, a2)), neg<bits>(helper));
        C e5 = mul(d5, a3);
        C e6 = sat_add<bits>(mul(d6, a4), neg<bits>(helper));
        C e7 = d7;

        //stage 4 - matches BSV rstage5
        C f0 = e0;
        C f1 = e1;
        C f2 = sat_add<bits>(e2, e3);
        C f3 = sat_add<bits>(e3, neg<bits>(e2));
        C f4 = e4;
        C f5 = sat_add<bits>(e5, e7);
        C f6 = e6;
        C f7 = sat_add<bits>(e7, neg<bits>(e5));

        //stage 5 - matches BSV rstage6 + output reorder
        freqs[0] = f0;
        freqs[4] = f1;
        freqs[2] = f2;
        freqs[6] = f3;
        freqs[5] = sat_add<bits>(f4, f7);
        freqs[1] = sat_add<bits>(f5, f6);
        freqs[7] = sat_add<bits>(neg<bits>(f6), f5);
        freqs[3] = sat_add<bits>(f7, neg<bits>(f4));
    }

    //
    // Optimized 1D AAN DCT variant - matches DCT1D safe_arith=False.
    // Additions wrap and fixed-point multiplies truncate instead of rounding.
    //
    template<int f_scale, int bits = 16>
    void dct1d_aan_fixed_optimized(std::span<coeff_t<bits>, 8> block, std::span<coeff_t<bits>, 8> freqs) {
        using C = coeff_t<bits>;
        using W = wide_t<bits>;
        constexpr W a1 = static_cast<W>(0.707106781 * (1 << f_scale) + 0.5);
        constexpr W a2 = static_cast<W>(0.541196100 * (1 << f_scale) + 0.5);
        constexpr W a3 = a1;
        constexpr W a4 = static_cast<W>(1.306562964 * (1 << f_scale) + 0.5);
        constexpr W a5 = static_cast<W>(0.382683432 * (1 << f_scale) + 0.5);

        auto mul = [](C val, W mult) -> C {
            return scaled_mul_trunc<f_scale, bits>(static_cast<W>(val), mult);
        };

        C b0 = wrap_add<bits>(block[0], block[7]);
        C b1 = wrap_add<bits>(block[1], block[6]);
        C b2 = wrap_add<bits>(block[2], block[5]);
        C b3 = wrap_add<bits>(block[3], block[4]);
        C b4 = wrap_add<bits>(neg<bits>(block[4]), block[3]);
        C b5 = wrap_add<bits>(neg<bits>(block[5]), block[2]);
        C b6 = wrap_add<bits>(neg<bits>(block[6]), block[1]);
        C b7 = wrap_add<bits>(neg<bits>(block[7]), block[0]);

        C c0 = wrap_add<bits>(b0, b3);
        C c1 = wrap_add<bits>(b1, b2);
        C c2 = wrap_add<bits>(neg<bits>(b2), b1);
        C c3 = wrap_add<bits>(neg<bits>(b3), b0);
        C c4 = wrap_add<bits>(neg<bits>(b4), neg<bits>(b5));
        C c5 = wrap_add<bits>(b5, b6);
        C c6 = wrap_add<bits>(b6, b7);
        C c7 = b7;

        C d0 = wrap_add<bits>(c0, c1);
        C d1 = wrap_add<bits>(neg<bits>(c1), c0);
        C d2 = wrap_add<bits>(c2, c3);
        C d3 = c3;
        C d4 = c4;
        C d5 = c5;
        C d6 = c6;
        C d7 = c7;

        C helper = mul(wrap_add<bits>(d4, d6), a5);

        C e0 = d0;
        C e1 = d1;
        C e2 = mul(d2, a1);
        C e3 = d3;
        C e4 = wrap_add<bits>(neg<bits>(mul(d4, a2)), neg<bits>(helper));
        C e5 = mul(d5, a3);
        C e6 = wrap_add<bits>(mul(d6, a4), neg<bits>(helper));
        C e7 = d7;

        C f0 = e0;
        C f1 = e1;
        C f2 = wrap_add<bits>(e2, e3);
        C f3 = wrap_add<bits>(e3, neg<bits>(e2));
        C f4 = e4;
        C f5 = wrap_add<bits>(e5, e7);
        C f6 = e6;
        C f7 = wrap_add<bits>(e7, neg<bits>(e5));

        freqs[0] = f0;
        freqs[4] = f1;
        freqs[2] = f2;
        freqs[6] = f3;
        freqs[5] = wrap_add<bits>(f4, f7);
        freqs[1] = wrap_add<bits>(f5, f6);
        freqs[7] = wrap_add<bits>(neg<bits>(f6), f5);
        freqs[3] = wrap_add<bits>(f7, neg<bits>(f4));
    }

    //
    // 2D DCT via separable 1D transforms (row then column) - matches DCT2D_Optimized.
    // Uses coeff_t<bits> temp storage matching BSV Int#(bits) pipeline FIFOs.
    //
    template<int dct_scale, int bits = 16>
    void dct2d_fixed(std::span<coeff_t<bits>, 64> block, std::span<coeff_t<bits>, 64> freqs) {
        coeff_t<bits> temp[64];

        //1D DCT on rows
        for (int y = 0; y < 8; ++y) {
            std::span<coeff_t<bits>, 8> row_in  { &block[y * 8], 8 };
            std::span<coeff_t<bits>, 8> row_out { &temp[y * 8], 8 };
            dct1d_aan_fixed<dct_scale, bits>(row_in, row_out);
        }

        //1D DCT on columns (transpose access)
        for (int x = 0; x < 8; ++x) {
            coeff_t<bits> col_in[8], col_out[8];
            for (int row = 0; row < 8; ++row) col_in[row] = temp[row * 8 + x];
            dct1d_aan_fixed<dct_scale, bits>(std::span<coeff_t<bits>, 8>{ col_in }, std::span<coeff_t<bits>, 8>{ col_out });
            for (int row = 0; row < 8; ++row) freqs[row * 8 + x] = col_out[row];
        }
    }

    //
    // 2D DCT variant for the optimized DCT path.
    //
    template<int dct_scale, int bits = 16>
    void dct2d_fixed_optimized(std::span<coeff_t<bits>, 64> block, std::span<coeff_t<bits>, 64> freqs) {
        coeff_t<bits> temp[64];

        for (int y = 0; y < 8; ++y) {
            std::span<coeff_t<bits>, 8> row_in  { &block[y * 8], 8 };
            std::span<coeff_t<bits>, 8> row_out { &temp[y * 8], 8 };
            dct1d_aan_fixed_optimized<dct_scale, bits>(row_in, row_out);
        }

        for (int x = 0; x < 8; ++x) {
            coeff_t<bits> col_in[8], col_out[8];
            for (int row = 0; row < 8; ++row) col_in[row] = temp[row * 8 + x];
            dct1d_aan_fixed_optimized<dct_scale, bits>(std::span<coeff_t<bits>, 8>{ col_in }, std::span<coeff_t<bits>, 8>{ col_out });
            for (int row = 0; row < 8; ++row) freqs[row * 8 + x] = col_out[row];
        }
    }

    //
    // Single-coefficient fixed-point quantization - mirrors Quantize.bsv scaled_mul_rt
    // with round=True.
    //
    template<int q_scale, int bits = 16>
    inline coeff_t<bits> quantize_coeff_fixed(coeff_t<bits> val, coeff_t<bits> scaled_mult) {
        wide_t<bits> prod = static_cast<wide_t<bits>>(val) * static_cast<wide_t<bits>>(scaled_mult);
        wide_t<bits> prod_m = prod + (wide_t<bits>{1} << (q_scale - 1));
        return truncate_to<bits>(prod_m >> q_scale);
    }

    //
    // Pre-compute HW-equivalent scaled quantization multipliers from a raw JPEG Q-table.
    // Absorbs AAN scaling factors: mult[i] = round(2^q_scale * s[row] * s[col] / Q[i])
    // This matches the table initialization in Quantize.bsv.
    //
    template<int q_scale, int bits = 16>
    void compute_scaled_quant_table(std::span<const uint8_t, 64> raw_q, std::array<coeff_t<bits>, 64> &out_mults) {
        double s[8];
        compute_aan_scale_factors(s);
        constexpr double scale = static_cast<double>(1 << q_scale);

        for (int i = 0; i < 64; ++i) {
            int row = i / 8;
            int col = i % 8;
            double scale_factor = (scale * s[row] * s[col]) / static_cast<double>(raw_q[i]);
            out_mults[i] = static_cast<coeff_t<bits>>(std::round(scale_factor));
        }
    }

}

#endif
