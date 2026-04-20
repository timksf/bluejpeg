#ifndef __FIXED_POINT_PIPELINE_HPP__
#define __FIXED_POINT_PIPELINE_HPP__

/*
    Factory functions returning callables that satisfy the dct_2d_fn, quantize_block_fn,
    and reorder_block_fn concepts from jpeg_types.hpp.
    
    These plug the fixed-point kernels from jpeg_fixed_point.hpp into the generic
    encode_jpeg pipeline to produce a bit-accurate HW model.

    The bits template parameter (default 16) selects the data path width,
    matching BSV Int#(bits). For bits <= 16 the coefficient type is int16_t;
    for bits <= 32 it is int32_t.
*/

#include "jpeg_types.hpp"
#include "jpeg_fixed_point.hpp"

#include <cstdint>
#include <span>
#include <array>

namespace fixedpoint_pipeline {

    //returns a lambda satisfying dct_2d_fn that performs fixed-point 2D AAN DCT.
    template<int dct_scale, int bits = 16>
    auto make_fixed_dct() {
        using coeff = jpeg_fixedpoint::coeff_t<bits>;
        return [](std::span<coeff, 64> in, std::span<coeff, 64> out) {
            jpeg_fixedpoint::dct2d_fixed<dct_scale, bits>(in, out);
        };
    }

    //returns a lambda satisfying quantize_block_fn.
    //computes scaled multipliers from the raw Q-table (absorbing AAN factors) at each call,
    //then applies fixed-point quantization per coefficient.
    template<int q_scale, int bits = 16>
    auto make_fixed_quantize() {
        using coeff = jpeg_fixedpoint::coeff_t<bits>;
        return [](std::span<coeff, 64> block, std::span<const uint8_t, 64> raw_q_table) {
            std::array<coeff, 64> scaled_mults;
            //TODO: move scaling outside this function
            jpeg_fixedpoint::compute_scaled_quant_table<q_scale, bits>(raw_q_table, scaled_mults);
            for (size_t i = 0; i < 64; ++i) {
                block[i] = jpeg_fixedpoint::quantize_coeff_fixed<q_scale, bits>(block[i], scaled_mults[i]);
            }
        };
    }

    //returns a lambda satisfying reorder_block_fn using the standard JPEG zigzag order.
    template<int bits = 16>
    auto make_zigzag() {
        using coeff = jpeg_fixedpoint::coeff_t<bits>;
        return [](std::span<coeff, 64> in, std::span<coeff, 64> out) {
            for (size_t i = 0; i < 64; ++i)
                out[i] = in[zigzag[i]];
        };
    }

}

#endif // __FIXED_POINT_PIPELINE_HPP__
