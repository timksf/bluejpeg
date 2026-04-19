#ifndef __FIXED_POINT_PIPELINE_HPP__
#define __FIXED_POINT_PIPELINE_HPP__

/*
    Factory functions returning callables that satisfy the dct_2d_fn, quantize_block_fn,
    and reorder_block_fn concepts from jpeg_types.hpp.
    
    These plug the fixed-point kernels from jpeg_fixed_point.hpp into the generic
    encode_jpeg pipeline to produce a bit-accurate HW model.
*/

#include "jpeg_types.hpp"
#include "jpeg_fixed_point.hpp"

#include <cstdint>
#include <span>
#include <array>

namespace fixedpoint_pipeline {

    // Returns a lambda satisfying dct_2d_fn that performs fixed-point 2D AAN DCT.
    template<int dct_scale>
    auto make_fixed_dct() {
        return [](std::span<int16_t, 64> in, std::span<int16_t, 64> out) {
            fixedpoint::dct2d_fixed<dct_scale>(in, out);
        };
    }

    // Returns a lambda satisfying quantize_block_fn.
    // Pre-computes scaled multipliers from the raw Q-table (absorbing AAN factors)
    // and captures them. Applies fixed-point quantization per coefficient.
    template<int q_scale>
    auto make_fixed_quantize(std::span<const uint8_t, 64> raw_q_table) {
        std::array<int16_t, 64> scaled_mults;
        fixedpoint::compute_scaled_quant_table<q_scale>(raw_q_table, scaled_mults);
        return [scaled_mults](std::span<int16_t, 64> block) {
            for (size_t i = 0; i < 64; ++i) {
                block[i] = fixedpoint::quantize_coeff_fixed<q_scale>(block[i], scaled_mults[i]);
            }
        };
    }

    // Returns a lambda satisfying reorder_block_fn using the standard JPEG zigzag order.
    inline auto make_zigzag() {
        return [](std::span<int16_t, 64> in, std::span<int16_t, 64> out) {
            for (size_t i = 0; i < 64; ++i)
                out[i] = in[zigzag[i]];
        };
    }

} // namespace fixedpoint_pipeline

#endif // __FIXED_POINT_PIPELINE_HPP__
