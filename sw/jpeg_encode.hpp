#ifndef __JPEG_ENCODE_HPP__
#define __JPEG_ENCODE_HPP__

#include <cstdint>
#include <algorithm>
#include <cmath>
#include <iterator>
#include <array>
#include <ranges>
#include <span>

#include "bmp.hpp"
#include "util.hpp"
#include "jpeg_types.hpp"
#include "jpeghuffman.hpp"
#include "jpegwriter.hpp"
#include "dct.hpp"


namespace jpegencode {

    namespace rng = std::ranges;

    struct jpeg_huffman_table_t {
        std::span<const uint8_t> bits;
        std::span<const uint8_t> values;
    };

    struct jpeg_huffman_table_set_t {
        jpeg_huffman_table_t luma_dc;
        jpeg_huffman_table_t luma_ac;
        jpeg_huffman_table_t chroma_dc;
        jpeg_huffman_table_t chroma_ac;
    };

    inline constexpr std::array<uint8_t, 16> std_dc_luma_bits = {
        0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0
    };
    inline constexpr std::array<uint8_t, 16> std_dc_chroma_bits = {
        0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0
    };
    inline constexpr std::array<uint8_t, 16> std_ac_luma_bits = {
        0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125
    };
    inline constexpr std::array<uint8_t, 16> std_ac_chroma_bits = {
        0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119
    };

    inline constexpr std::array<uint8_t, 12> std_dc_values = {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
    };

    inline constexpr std::array<uint8_t, 162> std_ac_luma_values = {
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12,
        0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
        0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0,
        0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16,
        0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
        0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
        0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
        0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
        0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
        0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
        0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5,
        0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4,
        0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
        0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
        0xF9, 0xFA
    };

    inline constexpr std::array<uint8_t, 162> std_ac_chroma_values = {
        0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21,
        0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
        0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
        0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0,
        0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34,
        0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
        0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38,
        0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
        0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
        0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
        0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78,
        0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 
        0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 
        0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 
        0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 
        0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 
        0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 
        0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 
        0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 
        0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 
        0xF9, 0xFA
    };

    inline const jpeg_huffman_table_set_t &default_huffman_tables() {
        static const jpeg_huffman_table_set_t tables {
            .luma_dc = { std::span{ std_dc_luma_bits }, std::span{ std_dc_values } },
            .luma_ac = { std::span{ std_ac_luma_bits }, std::span{ std_ac_luma_values } },
            .chroma_dc = { std::span{ std_dc_chroma_bits }, std::span{ std_dc_values } },
            .chroma_ac = { std::span{ std_ac_chroma_bits }, std::span{ std_ac_chroma_values } },
        };
        return tables;
    }

    struct jpeg_params_t {
        size_t width;
        size_t height;
        int quality;
        const std::string output_filename = "out";
        subsampling_t subsampling_mode;
        bool use_predefined_huffman_tables = false;
        const jpeg_huffman_table_set_t *huffman_tables = nullptr;
    };
    
    static uint8_t std_luma_quant[64] = { 
        16, 11, 10, 16,  24,  40,  51,  61,
        12, 12, 14, 19,  26,  58,  60,  55,
        14, 13, 16, 24,  40,  57,  69,  56,
        14, 17, 22, 29,  51,  87,  80,  62,
        18, 22, 37, 56,  68, 109, 103,  77,
        24, 35, 55, 64,  81, 104, 113,  92,
        49, 64, 78, 87, 103, 121, 120, 101,
        72, 92, 95, 98, 112, 100, 103,  99
    };
    static uint8_t std_chroma_quant[64] = { 
        17, 18, 24, 47, 99, 99, 99, 99,
        18, 21, 26, 66, 99, 99, 99, 99,
        24, 26, 56, 99, 99, 99, 99, 99,
        47, 66, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99
    };

    template<size_t N>
    static const std::array<float, N*N> cosine_lookup = [](){
        std::array<float, N*N> lookup;
        float div = 1.f/(2.f*N);
        for(auto i = 0; i < N; i++){
            for(auto j = 0; j < N; j++){
                lookup[i*8+j] = cosf((2*i+1)*j*M_PI*div);
            }
        }
        return lookup;
    }();

    template<numeric_type T, size_t N>
    void set_quality(std::span<T, N> quant_table, int quality) {
        //https://stackoverflow.com/questions/29215879/how-can-i-generalize-the-quantization-matrix-in-jpeg-compression
        assert(1 <= quality && quality <= 100 && "Quality as percentage has to be in range 1 <= q <= 100");
        int S;
        if(quality < 50){
            S = 5000 / quality;
        } else {
            S = 200 - 2*quality;
        }
        rng::for_each(quant_table, [&S](auto &q){ 
            q = (S*q + 50) / 100; 
            q = q == 0 ? 1 : q;
        });
// #define MAX(a,b)  (((a)>(b))?(a):(b))
// #define MIN(a,b)  (((a)<(b))?(a):(b))
// #define CLIP(n, min, max) MIN((MAX((n),(min))), (max))
//             for (int i=0; i<64; i++) {
//                 double r = CLIP((100-quality)/50.0 * quant_table[i], 1, 255);
// 		        quant_table[i] = r;
//             }
// #undef CLIP
// #undef MIN
// #undef MAX
    }

    template<rng::random_access_range Range>
        requires (
            (
                std::integral<rng::range_value_t<Range>> ||
                std::floating_point<rng::range_value_t<Range>>
            ) &&
            rng::sized_range<Range>
        )
    void subsample(Range &&data, size_t height, size_t width, subsampling_t mode) {
        using T = rng::range_value_t<Range>;
        if(!(width*height == rng::size(data))){
            std::cerr << "Supplied data does not fit height and width" << std::endl;
            return;
        }
        if(mode == subsampling_t::YCBCR_422){
            for(auto idx = 0; idx < height*width; idx+=2){
                auto sum = data[idx] + data[idx+1];
                T avg = static_cast<T>(std::round(sum / 2.f));
                data[idx] = avg;
                data[idx+1] = avg;
            }
        } else if(mode == subsampling_t::YCBCR_420) {
            for(auto i = 0; i < height; i+=2){
                for(auto j = 0; j < width; j+=2){
                    auto sum = data[i*width+j] + data[i*width+j+1];
                    sum += data[(i+1)*width+j] + data[(i+1)*width+j+1];
                    T avg = static_cast<T>(std::round(sum / 4.f));
                    data[i*width+j] = avg;
                    data[i*width+j+1] = avg;
                    data[(i+1)*width+j] = avg;
                    data[(i+1)*width+j+1] = avg;
                }
            }
        }
        //YCBCR_444 does not modify the input data at all
    }

    template<typename t, typename t1>
    void get_block8x8(std::vector<t>& src, t1* dst, size_t x, size_t y, size_t w, size_t h){
        auto base_idx = y*w+x;
        for(auto i = 0; i < 8; i++){
            for(auto j = 0; j < 8; j++){
                auto idx = base_idx+i*w+j;
                dst[i*8+j] = src[idx];
                // std::cout << (i*8)+j << std::endl;
            }
        }
    }

    template<numeric_type T, numeric_type R, size_t N>
    void quantize(std::span<T, N> block, std::span<R, N> coeffs) {
        for(auto&& [v, c] : std::views::zip(block, coeffs)){
            v /= c;
        }
    }

    template<typename T, size_t N>
    void reorder(std::span<T, N> block, std::span<T, N> result, std::span<size_t, N> indices) {
        for(size_t i = 0; i < N; ++i)
            result[i] = block[indices[i]];
    }

    /*
        Performs all JPEG encoding steps except entropy coding for a single channel.
        The steps are:
        2D DCT-II -> quantization -> reordering (zigzag) -> DC diff calculation
        
        These steps are performed in 8x8 blocks.
        The processing functions (DCT, quantization, reordering) are injected as callables,
        constrained by the concepts defined in jpeg_types.hpp.
    */
    template<rng::random_access_range Channel, dct_2d_fn DctFn, quantize_block_fn QuantFn, reorder_block_fn ReorderFn>
    auto process_channel(
        Channel&& channel,
        size_t width,
        size_t height,
        DctFn&& dct_fn,
        QuantFn&& quant_fn,
        ReorderFn&& reorder_fn,
        bool debug
    ){
        assert(width % 8 == 0 && "Width is not a multiple of 8");
        assert(height % 8 == 0 && "Height is not a multiple of 8");

        std::vector<int16_t> dcts;
        for(int i = 0; i < height; i+=8){
            for(int j = 0; j < width; j+=8){
                int16_t block[64] = { 0 };
                int16_t dct[64] = { 0 };
                int16_t zigzagged[64] = { 0 };

                //extract coding unit
                get_block8x8(channel, block, j, i, width, height);
                
#ifdef DEBUG
                if(debug) {
                    std::cout << std::format("block{}:", (i/8*width/8)+j/8) << std::endl;
                    print_range_2d_formatted("{:4d}", std::span{ block }, 8, 8);
                }
#endif
                
                //mean shift to 0
                for(auto l = 0; l < 64; l++)
                    block[l] -= 128;
                
                //perform 2D DCT-II
                dct_fn(std::span<int16_t, 64>{ block }, std::span<int16_t, 64>{ dct });

#ifdef DEBUG
                if(debug) {
                    std::cout << std::endl << "after DCT:" << std::endl;
                    print_range_2d_formatted("{:4d}", dct, 8, 8);
                }
#endif

                //quantize dct values
                quant_fn(std::span<int16_t, 64>{ dct });

#ifdef DEBUG
                if(debug) {
                    std::cout << std::endl << "after quantization:" << std::endl;
                    print_range_2d_formatted("{:4d}", dct, 8, 8);
                }
#endif

                //reorder into zigzag pattern
                reorder_fn(std::span<int16_t, 64>{ dct }, std::span<int16_t, 64>{ zigzagged });

#ifdef DEBUG
                if(debug) {
                    std::cout << std::endl << "after zigzagging:";
                    print_range_formatted("{:4d}", zigzagged);
                    std::cout << std::endl;
                }
#endif

                //copy reordered data into result sequence
                rng::copy(zigzagged, std::back_inserter(dcts));
            }
        }

        //dcts contains zigzagged, quantized DCT coefficients (ZZ)
        return dcts;
    }

    template<rng::random_access_range Channel, dct_2d_fn DctFn, quantize_block_fn QuantFn, reorder_block_fn ReorderFn>
    auto process_luma(
        Channel &&luma,
        size_t width,
        size_t height,
        DctFn&& dct_fn,
        QuantFn&& quant_fn,
        ReorderFn&& reorder_fn,
        bool debug
    ) {
        return process_channel(luma, width, height, dct_fn, quant_fn, reorder_fn, debug);
    }

    template<rng::random_access_range Channel, dct_2d_fn DctFn, quantize_block_fn QuantFn, reorder_block_fn ReorderFn>
    auto process_chroma(
        Channel &&chroma,
        size_t width,
        size_t height,
        subsampling_t subsampling_mode,
        DctFn&& dct_fn,
        QuantFn&& quant_fn,
        ReorderFn&& reorder_fn,
        bool debug
    ) {
        //after subsampling, extract the new coding blocks with strided access
        using T = rng::range_value_t<Channel>;
        std::vector<T> chroma_sub;
        int div_vert = 1, div_horiz = 1;
        if(subsampling_mode == subsampling_t::YCBCR_444) {
            rng::copy(chroma, std::back_inserter(chroma_sub));
        } else if(subsampling_mode == subsampling_t::YCBCR_422){
            div_horiz = 2;
            //only need to skip every second element in the horizontal direction
            rng::copy(chroma | std::views::stride(2), std::back_inserter(chroma_sub));
            assert(chroma_sub.size() == chroma.size()/2 && "Subsampling failed");
        } else if(subsampling_mode == subsampling_t::YCBCR_420){
            div_horiz = 2;
            div_vert = 2;
            //skip every second horizontal element and every second vertical row
            auto subsample_extract = 
                std::views::chunk(width)                        //arrange in rows
                | std::views::stride(2)                         //drop every second row
                | std::views::transform(std::views::stride(2))  //drop every second element in each non-dropped row
                | std::views::join;
            rng::copy(chroma | subsample_extract, std::back_inserter(chroma_sub));
            assert(chroma_sub.size() == chroma.size()/4 && "Subsampling failed");
        }
        return process_channel(chroma_sub, width / div_horiz, height / div_vert, dct_fn, quant_fn, reorder_fn, debug);
    }

    /*
        Generic JPEG encoder. Processing functions (DCT, quantization, reordering) are injected
        as callables constrained by the concepts in jpeg_types.hpp.
        
        The quantization callables capture their respective tables internally.
        Raw quantization tables must still be provided for the JPEG file header.
    */
    template<
        rng::input_range InRange,
        dct_2d_fn DctFn,
        quantize_block_fn QuantLumaFn,
        quantize_block_fn QuantChromaFn,
        reorder_block_fn ReorderFn
    > requires rng::sized_range<InRange>
    uintmax_t encode_jpeg(
        InRange &&img_ycbcr,
        const jpeg_params_t &params,
        std::span<uint8_t, 64> luma_quantizer,
        std::span<uint8_t, 64> chroma_quantizer,
        DctFn&& dct_fn,
        QuantLumaFn&& quant_luma_fn,
        QuantChromaFn&& quant_chroma_fn,
        ReorderFn&& reorder_fn,
        bool debug = false
    ){
        JPEGHuffmanCode huff_luma_dc, huff_luma_ac, huff_chroma_dc, huff_chroma_ac;
        std::vector<uint8_t> Y, CB, CR;

        //separate channels
        Y.reserve(img_ycbcr.size());
        CB.reserve(img_ycbcr.size());
        CR.reserve(img_ycbcr.size());
        rng::copy(img_ycbcr | std::views::transform([](const ycbcr_t &e){return e.y;}),  std::back_inserter(Y));
        rng::copy(img_ycbcr | std::views::transform([](const ycbcr_t &e){return e.cb;}), std::back_inserter(CB));
        rng::copy(img_ycbcr | std::views::transform([](const ycbcr_t &e){return e.cr;}), std::back_inserter(CR));

        //subsample chroma
        subsample(CR, params.height, params.width, params.subsampling_mode);
        subsample(CB, params.height, params.width, params.subsampling_mode);

#ifdef DEBUG
        if(debug) {
            std::cout << "Quantization Tables" << std::endl;
            std::cout << "LUMA: " << std::endl;
            print_range_2d_formatted("{:d}", luma_quantizer, 8, 8);
            std::cout << std::endl << "CHROMA: " << std::endl;
            print_range_2d_formatted("{:d}", chroma_quantizer, 8, 8);
            std::cout << std::endl;
        }
#endif

        //perform DCT transformation
        auto y_dct = process_luma(Y, params.width, params.height, dct_fn, quant_luma_fn, reorder_fn, debug);
        auto cb_dct = process_chroma(CB, params.width, params.height, params.subsampling_mode, dct_fn, quant_chroma_fn, reorder_fn, debug);
        auto cr_dct = process_chroma(CR, params.width, params.height, params.subsampling_mode, dct_fn, quant_chroma_fn, reorder_fn, debug);

        if(params.use_predefined_huffman_tables) {
            auto &tables = params.huffman_tables == nullptr ? default_huffman_tables() : *params.huffman_tables;
            huff_luma_dc.init_from_huffvals(tables.luma_dc.bits, tables.luma_dc.values, JPEGCoeffCategory::DC);
            huff_luma_ac.init_from_huffvals(tables.luma_ac.bits, tables.luma_ac.values, JPEGCoeffCategory::AC);
            huff_chroma_dc.init_from_huffvals(tables.chroma_dc.bits, tables.chroma_dc.values, JPEGCoeffCategory::DC);
            huff_chroma_ac.init_from_huffvals(tables.chroma_ac.bits, tables.chroma_ac.values, JPEGCoeffCategory::AC);
        } else {
            // Concatenate raw chroma DCTs so DC frequencies are derived from the actual, not already-differenced, symbols.
            std::vector<int16_t> chroma_dct;
            chroma_dct.reserve(cb_dct.size() + cr_dct.size());
            rng::copy(cb_dct, std::back_inserter(chroma_dct));
            rng::copy(cr_dct, std::back_inserter(chroma_dct));

            huff_luma_dc.init_from_coeffs(y_dct, JPEGCoeffCategory::DC);
            huff_luma_ac.init_from_coeffs(y_dct, JPEGCoeffCategory::AC);
            huff_chroma_dc.init_from_coeffs(chroma_dct, JPEGCoeffCategory::DC);
            huff_chroma_ac.init_from_coeffs(chroma_dct, JPEGCoeffCategory::AC);
        }

        // DC values in the entropy-coded scan must always be differenced, regardless of how the Huffman tables were built.
        JPEGHuffmanCode::dc_diff(y_dct | std::views::stride(64));
        JPEGHuffmanCode::dc_diff(cb_dct | std::views::stride(64));
        JPEGHuffmanCode::dc_diff(cr_dct | std::views::stride(64));

#ifdef DEBUG
        if(debug) {
            std::cout << "Huffman Table Information" << std::endl;
            JPEGHuffmanPrinter::print_symbol_freqs(huff_luma_dc, huff_luma_ac, huff_chroma_dc, huff_chroma_ac);
        }
#endif

        huff_luma_dc.build_table();
        huff_luma_ac.build_table();
        huff_chroma_dc.build_table();
        huff_chroma_ac.build_table();

#ifdef DEBUG
        if(debug) {
            JPEGHuffmanPrinter::print_symbol_lengths(huff_luma_dc, huff_luma_ac, huff_chroma_dc, huff_chroma_ac);
            JPEGHuffmanPrinter::print_encoded_symb_freqs(huff_luma_dc, huff_luma_ac, huff_chroma_dc, huff_chroma_ac);
            JPEGHuffmanPrinter::print_sorted_code_lengths(huff_luma_dc, huff_luma_ac, huff_chroma_dc, huff_chroma_ac);
            JPEGHuffmanPrinter::print_sorted_codes(huff_luma_dc, huff_luma_ac, huff_chroma_dc, huff_chroma_ac);
        }
#endif

        uintmax_t s = jpegwriter::write_jpeg_file(
            params.output_filename,
            params.width,
            params.height,
            y_dct,
            cb_dct,
            cr_dct, 
            params.subsampling_mode,
            luma_quantizer,
            chroma_quantizer,
            huff_luma_dc,
            huff_luma_ac,
            huff_chroma_dc,
            huff_chroma_ac
        );
        return s;
    }

    /*
        Default float-based JPEG encoder — preserves the original API.
        Uses floating-point AAN DCT, integer-division quantization, and standard zigzag reorder.
    */
    template<rng::input_range InRange> requires rng::sized_range<InRange>
    uintmax_t encode_jpeg(InRange &&img_ycbcr, const jpeg_params_t &params, bool debug = false){
        uint8_t luma_quantizer[64], chroma_quantizer[64];
        rng::copy(std_luma_quant, std::end(std_luma_quant), luma_quantizer);
        rng::copy(std_chroma_quant, std::end(std_chroma_quant), chroma_quantizer);

        //setup quantization tables
        set_quality(std::span{ luma_quantizer }, params.quality);
        set_quality(std::span{ chroma_quantizer }, params.quality);

        // Float AAN DCT
        auto dct_fn = [](std::span<int16_t, 64> in, std::span<int16_t, 64> out) {
            dct::dct2d_as_1d<int16_t, 8>(in, out, dct::dct1d_aan_unscaled<int16_t, float>);
        };

        // Integer-division quantization (captures table by copy)
        auto make_quant_fn = [](std::span<uint8_t, 64> table) {
            std::array<uint8_t, 64> qtable;
            std::copy(table.begin(), table.end(), qtable.begin());
            return [qtable](std::span<int16_t, 64> block) {
                for(size_t i = 0; i < 64; ++i)
                    block[i] /= qtable[i];
            };
        };

        // Standard zigzag reorder
        auto reorder_fn = [](std::span<int16_t, 64> in, std::span<int16_t, 64> out) {
            reorder(in, out, std::span{ zigzag });
        };

        return encode_jpeg(
            std::forward<InRange>(img_ycbcr),
            params,
            std::span<uint8_t, 64>{ luma_quantizer },
            std::span<uint8_t, 64>{ chroma_quantizer },
            dct_fn,
            make_quant_fn(std::span<uint8_t, 64>{ luma_quantizer }),
            make_quant_fn(std::span<uint8_t, 64>{ chroma_quantizer }),
            reorder_fn,
            debug
        );
    }   

}

#endif //__JPEG_ENCODE_HPP__