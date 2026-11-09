
#include "../../../../sw/dct.hpp"
#include "../../../../sw/util.hpp"
#include "../../../../sw/jpeg_encode.hpp"
#include "jpeg_fixed_point.hpp"
#include <cstdint>
#include <span>
#include <cstdlib>
#include <cmath>
#include <queue>

enum class RLETagType : uint8_t {
    DCDiff = 0,
    EOB = 1,
    ZRL = 2,
    AC = 3
};

struct RLETag {
    RLETagType type;
    uint8_t run;
    int16_t val;
};

class RLEModel {
private:
    std::queue<RLETag> _tags;
    int16_t _prev_dc[2] = { 0 };
    uint8_t _mode = 0; //luma or chroma for interleaved data

public:
    void set_mode(uint8_t mode) { 
        _mode = mode & 0x1; 
    }

    void rewind() {
        _prev_dc[0] = _prev_dc[1] =  0;
        while(!_tags.empty()) _tags.pop();
    }

    void process_block(const int16_t *block) {
        //see write_scan in jpegwriter.hpp

        //dc values
        int16_t dc = block[0];
        int16_t diff = dc - _prev_dc[_mode];
        _prev_dc[_mode] = dc;
        _tags.push({RLETagType::DCDiff, 0, diff});

        //ac values
        int consecutive_zeros = 0;
        int last_nonzero = 63;
        
        while(last_nonzero > 0 && block[last_nonzero] == 0) //move from back to front until nonzero encountered
            last_nonzero--;

        for (int i = 1; i <= last_nonzero; ++i) {
            if (block[i] == 0) {
                consecutive_zeros++;
                if (consecutive_zeros == 16) {
                    _tags.push({RLETagType::ZRL, 0, 0});
                    consecutive_zeros = 0;
                }
            } else {
                _tags.push({RLETagType::AC, static_cast<uint8_t>(consecutive_zeros), block[i]});
                consecutive_zeros = 0;
            }
        }

        //emit EOB if block ended on a zero
        if (last_nonzero < 63) {
            _tags.push({RLETagType::EOB, 0, 0});
        }
    }

    bool has_next() const { return !_tags.empty(); }
    uint8_t next_type() const { return static_cast<uint8_t>(_tags.front().type); }
    int16_t next_val() const { return _tags.front().val; }
    uint8_t next_run() const { return _tags.front().run; }
    void pop() { _tags.pop(); }
};

extern "C" {

    // Wrapper for BSV: ActionValue#(Bit#(1024)) dct_2d_ref(Bit#(1024) in);
    // BSV ABI: Bit#(1024) is passed as unsigned int* (array of 32 uint32_t).
    // Return value pointer is passed as first argument.
    void dct_2d_i16_ref(uint32_t *output_packed, const uint32_t *input_packed, bool scale) {
        int16_t input[64];
        int16_t output[64];

        //unpack 16-bit values from 32-bit chunks
        for(int i = 0; i < 32; ++i) {
            uint32_t val = input_packed[i];
            input[2*i] = (int16_t)(val & 0xFFFF);
            input[2*i+1] = (int16_t)(val >> 16);
        }

        std::span<int16_t, 64> in_span(input, 64);
        std::span<int16_t, 64> out_span(output, 64);

        // std::cout << std::format("C++ BLOCK") << std::endl;
        // print_range_2d_formatted("{:4d}", in_span, 8, 8);
        // std::cout << std::endl;

        dct::dct2d_as_1d<int16_t, 8>(in_span, out_span, [&scale](std::span<int16_t, 8> in, std::span<int16_t, 8> out) {
            dct::dct1d_aan<int16_t, float>(in, out, scale); // scale=false for unscaled AAN
        });

        //pack 16-bit coefficients to 32-bit chunks
        for(int i = 0; i < 32; ++i) {
            uint32_t val = (uint16_t)output[2*i];
            val |= ((uint32_t)((uint16_t)output[2*i+1])) << 16;
            output_packed[i] = val;
        }
    }

    void dct_2d_i8_ref(uint32_t *output_packed, const uint32_t *input_packed, bool scale) {
        int8_t input[64];
        int8_t output[64];

        //unpack 8-bit values from 32-bit chunks
        for(int i = 0; i < 16; ++i) {
            uint32_t val = input_packed[i];
            input[4*i] = (int8_t)(val & 0xFF);
            input[4*i+1] = (int8_t)((val >> 8) & 0xFF);
            input[4*i+2] = (int8_t)((val >> 16) & 0xFF);
            input[4*i+3] = (int8_t)((val >> 24) & 0xFF);
        }

        std::span<int8_t, 64> in_span(input, 64);
        std::span<int8_t, 64> out_span(output, 64);

        // std::cout << std::format("C++ BLOCK") << std::endl;
        // print_range_2d_formatted("{:4d}", in_span, 8, 8);
        // std::cout << std::endl;

        dct::dct2d_as_1d<int8_t, 8>(in_span, out_span, [&scale](std::span<int8_t, 8> in, std::span<int8_t, 8> out) {
            dct::dct1d_aan<int8_t, float>(in, out, scale); // scale=false for unscaled AAN
        });

        //pack 8-bit coefficients to 32-bit chunks
        for(int i = 0; i < 16; ++i) {
            uint32_t val = (uint8_t)output[4*i];
            val |= ((uint32_t)((uint8_t)output[4*i+1])) << 8;
            val |= ((uint32_t)((uint8_t)output[4*i+2])) << 16;
            val |= ((uint32_t)((uint8_t)output[4*i+3])) << 24;
            output_packed[i] = val;
        }
    }

    void dct_1d_i8_ref_raw(uint32_t *output_packed, const uint32_t *input_packed, bool scale) {
        int8_t input[8];
        int8_t output[8];

        for(int i = 0; i < 2; ++i) {
            uint32_t val = input_packed[i];
            input[4*i] = (int8_t)(val & 0xFF);
            input[4*i+1] = (int8_t)((val >> 8) & 0xFF);
            input[4*i+2] = (int8_t)((val >> 16) & 0xFF);
            input[4*i+3] = (int8_t)((val >> 24) & 0xFF);
        }

        std::span<int8_t, 8> in_span(input, 8);
        std::span<int8_t, 8> out_span(output, 8);

        // std::cout << std::format("C++ ROW") << std::endl;
        // print_range_formatted("{:4d}", in_span);
        // std::cout << std::endl;

        dct::dct1d_aan<int8_t, float>(in_span, out_span, scale);

        for(int i = 0; i < 2; ++i) {
            uint32_t val = (uint8_t)output[4*i];
            val |= ((uint32_t)((uint8_t)output[4*i+1])) << 8;
            val |= ((uint32_t)((uint8_t)output[4*i+2])) << 16;
            val |= ((uint32_t)((uint8_t)output[4*i+3])) << 24;
            output_packed[i] = val;
        }
    }

    void dct_1d_i16_ref(uint32_t *output_packed, const uint32_t *input_packed, bool scale) {
        int16_t input[8];
        int16_t output[8];

        for(int i = 0; i < 4; ++i) {
            uint32_t val = input_packed[i];
            input[2*i] = (int16_t)(val & 0xFFFF);
            input[2*i+1] = (int16_t)(val >> 16);
        }

        std::span<int16_t, 8> in_span(input, 8);
        std::span<int16_t, 8> out_span(output, 8);

        dct::dct1d_aan<int16_t, float>(in_span, out_span, scale);

        for(int i = 0; i < 4; ++i) {
            uint32_t val = (uint16_t)output[2*i];
            val |= ((uint32_t)((uint16_t)output[2*i+1])) << 16;
            output_packed[i] = val;
        }
    }

    int16_t rand_i16(int32_t min, int32_t max) {
        int32_t range = max - min + 1;
        int32_t num = rand() % range + min;
        return num & 0xFFFF;
    }

    int16_t quant_ref_i16(int16_t v, uint32_t idx, bool luma_not_chroma, bool apply_aan, uint32_t f_scale) {
        using namespace jpegencode;
        if(idx > 63) {
            std::cerr << "Quantization encountered invalid index " << idx << std::endl;
            return INT16_MIN;
        }

        uint8_t *table = luma_not_chroma ? std_luma_quant : std_chroma_quant;
        double q = static_cast<double>(table[idx]);

        if (apply_aan) {
            static double s[8];
            static bool s_init = false;
            if (!s_init) {
                s[0] = 1.0 / (2.0 * std::sqrt(2.0));
                for (int i = 1; i < 8; ++i) {
                    s[i] = 1.0 / (4.0 * std::cos(i * M_PI / 16.0));
                }
                s_init = true;
            }

            uint32_t row = idx / 8;
            uint32_t col = idx % 8;

            //emulate hardware scaling with f_scale fractional fixed-point values
            double scale = std::pow(2.0, f_scale);
            double scale_factor = (scale * s[row] * s[col]) / q;
            int32_t mult        = static_cast<int32_t>(std::round(scale_factor));
            int32_t prod        = static_cast<int32_t>(v) * mult;
            int32_t prod_m      = prod + (1 << (f_scale - 1));
            
            return static_cast<int16_t>(std::floor(prod_m / scale));
        }

        return static_cast<int16_t>(std::round(static_cast<double>(v) / q));
    }


    void zigzag_ref_i16(uint32_t *output_packed, const uint32_t *input_packed, bool transposed) {
        int16_t input[64];
        int16_t output[64];

        //unpack 16-bit values from 32-bit chunks
        for(int i = 0; i < 32; ++i) {
            uint32_t val = input_packed[i];
            input[2*i] = (int16_t)(val & 0xFFFF);
            input[2*i+1] = (int16_t)(val >> 16);
        }

        std::span<int16_t, 64> in_span(input, 64);
        std::span<int16_t, 64> out_span(output, 64);

        size_t custom_zigzag[64];
        for(int i = 0; i < 64; ++i) {
            size_t idx = zigzag[i];
            custom_zigzag[i] = transposed ? ((idx % 8) * 8 + (idx / 8)) : idx;
        }

        jpegencode::reorder(in_span, out_span, std::span<size_t, 64>(custom_zigzag, 64));

        //pack 16-bit coefficients to 32-bit chunks
        for(int i = 0; i < 32; ++i) {
            uint32_t val = (uint16_t)output[2*i];
            val |= ((uint32_t)((uint16_t)output[2*i+1])) << 16;
            output_packed[i] = val;
        }
    }

    //fixed point AAN - delegates to shared header (jpeg_fixed_point.hpp)
    void dct1d_aan_fixed(std::span<int16_t, 8> block, std::span<int16_t, 8> freqs, int f_scale) {
        //runtime dispatch to compile-time scale; only 12 and 8 are used in practice
        if (f_scale == 12) {
            jpeg_fixedpoint::dct1d_aan_fixed<12>(block, freqs);
        } else if (f_scale == 8) {
            jpeg_fixedpoint::dct1d_aan_fixed<8>(block, freqs);
        } else {
            //fallback: use runtime-parameterized version for other scales
            //mirrors BSV pipeline: all intermediates are int16_t, additions saturate
            using jpeg_fixedpoint::sat_add;

            int32_t a1 = static_cast<int32_t>(std::round(0.707106781 * (1 << f_scale)));
            int32_t a2 = static_cast<int32_t>(std::round(0.541196100 * (1 << f_scale)));
            int32_t a3 = a1;
            int32_t a4 = static_cast<int32_t>(std::round(1.306562964 * (1 << f_scale)));
            int32_t a5 = static_cast<int32_t>(std::round(0.382683432 * (1 << f_scale)));

            auto mul = [&](int16_t val, int32_t mult) -> int16_t {
                int32_t prod = static_cast<int32_t>(val) * mult;
                return static_cast<int16_t>((prod + (1 << (f_scale - 1))) >> f_scale);
            };

            int16_t b0 = sat_add( block[0],  block[7]);
            int16_t b1 = sat_add( block[1],  block[6]);
            int16_t b2 = sat_add( block[2],  block[5]);
            int16_t b3 = sat_add( block[3],  block[4]);
            int16_t b4 = sat_add(static_cast<int16_t>(-block[4]), block[3]);
            int16_t b5 = sat_add(static_cast<int16_t>(-block[5]), block[2]);
            int16_t b6 = sat_add(static_cast<int16_t>(-block[6]), block[1]);
            int16_t b7 = sat_add(static_cast<int16_t>(-block[7]), block[0]);

            int16_t c0 = sat_add( b0,  b3); int16_t c1 = sat_add( b1,  b2);
            int16_t c2 = sat_add(static_cast<int16_t>(-b2), b1);
            int16_t c3 = sat_add(static_cast<int16_t>(-b3), b0);
            int16_t c4 = sat_add(static_cast<int16_t>(-b4), static_cast<int16_t>(-b5));
            int16_t c5 = sat_add( b5,  b6);
            int16_t c6 = sat_add( b6,  b7);
            int16_t c7 = b7;

            int16_t d0 = sat_add( c0,  c1); int16_t d1 = sat_add(static_cast<int16_t>(-c1), c0);
            int16_t d2 = sat_add( c2,  c3); int16_t d3 = c3;
            int16_t d4 = c4; int16_t d5 = c5; int16_t d6 = c6; int16_t d7 = c7;

            int16_t helper = mul(sat_add(d4, d6), a5);

            int16_t e0 = d0; int16_t e1 = d1;
            int16_t e2 = mul(d2, a1); int16_t e3 = d3;
            int16_t e4 = sat_add(static_cast<int16_t>(-mul(d4, a2)), static_cast<int16_t>(-helper));
            int16_t e5 = mul(d5, a3);
            int16_t e6 = sat_add(mul(d6, a4), static_cast<int16_t>(-helper));
            int16_t e7 = d7;

            int16_t f0 = e0; int16_t f1 = e1;
            int16_t f2 = sat_add( e2,  e3); int16_t f3 = sat_add( e3, static_cast<int16_t>(-e2));
            int16_t f4 = e4; int16_t f5 = sat_add( e5,  e7);
            int16_t f6 = e6; int16_t f7 = sat_add( e7, static_cast<int16_t>(-e5));

            freqs[0] = f0; freqs[4] = f1; freqs[2] = f2; freqs[6] = f3;
            freqs[5] = sat_add( f4,  f7); freqs[1] = sat_add( f5,  f6);
            freqs[7] = sat_add(static_cast<int16_t>(-f6), f5);
            freqs[3] = sat_add( f7, static_cast<int16_t>(-f4));
        }
    }

    void mcu_proc_ref(uint32_t *output_packed, const uint32_t *input_packed, uint8_t luma_not_chroma, uint8_t optimized_dct) {
        using namespace jpegencode;
        int16_t input[64];
        int16_t shifted[64];
        int16_t dct_out[64];
        int16_t quant_out[64];
        int16_t final_out[64];

        //unpack 8x8 16b from 32 32b values
        for(int i = 0; i < 32; ++i) {
            uint32_t val = input_packed[i];
            input[2*i] = (int16_t)(val & 0xFFFF);
            input[2*i+1] = (int16_t)(val >> 16);
        }

        //mean shift
        for (int i = 0; i < 64; ++i) {
            shifted[i] = input[i] - 128;
        }

        //dct - use shared fixed-point implementation
        if (optimized_dct) {
            jpeg_fixedpoint::dct2d_fixed_optimized<12>(
                std::span<int16_t, 64>(shifted, 64),
                std::span<int16_t, 64>(dct_out, 64)
            );
        } else {
            jpeg_fixedpoint::dct2d_fixed<12>(
                std::span<int16_t, 64>(shifted, 64),
                std::span<int16_t, 64>(dct_out, 64)
            );
        }

        //quantization - use shared fixed-point quantization
        std::array<int16_t, 64> scaled_mults;
        uint8_t *table = luma_not_chroma ? std_luma_quant : std_chroma_quant;
        jpeg_fixedpoint::compute_scaled_quant_table<12>(
            std::span<const uint8_t, 64>(table, 64),
            scaled_mults
        );
        for (int i = 0; i < 64; ++i) {
            quant_out[i] = jpeg_fixedpoint::quantize_coeff_fixed<12>(dct_out[i], scaled_mults[i]);
        }

        //zigzag
        reorder(
            std::span<int16_t, 64>(quant_out, 64),
            std::span<int16_t, 64>(final_out, 64),
            std::span{ zigzag }
        );

        //pack output
        for(int i = 0; i < 32; ++i) {
            uint32_t val = (uint16_t)final_out[2*i];
            val |= ((uint32_t)((uint16_t)final_out[2*i+1])) << 16;
            output_packed[i] = val;
        }
    }

    //RLE wrappers
    void *rle_model_create() {
        return new RLEModel();
    }

    void rle_model_destroy(void *ptr) {
        delete static_cast<RLEModel*>(ptr);
    }

    void rle_model_set_mode(void *ptr, uint8_t mode) {
        static_cast<RLEModel*>(ptr)->set_mode(mode);
    }

    void rle_model_rewind(void* ptr) {
        static_cast<RLEModel*>(ptr)->rewind();
    }

    void rle_model_process_block(const uint32_t *input_packed, void *ptr) {
        int16_t input[64];
        for(int i = 0; i < 32; ++i) {
            uint32_t val = input_packed[i];
            input[2*i] = (int16_t)(val & 0xFFFF);
            input[2*i+1] = (int16_t)(val >> 16);
        }
        static_cast<RLEModel*>(ptr)->process_block(input);
    }

    uint8_t rle_model_has_next(void *ptr) {
        return static_cast<RLEModel*>(ptr)->has_next() ? 1 : 0;
    }

    uint8_t rle_model_next_type(void *ptr) { return static_cast<RLEModel*>(ptr)->next_type(); }
    int16_t rle_model_next_val(void *ptr)  { return static_cast<RLEModel*>(ptr)->next_val(); }
    uint8_t rle_model_next_run(void *ptr)  { return static_cast<RLEModel*>(ptr)->next_run(); }
    
    void rle_model_pop(void *ptr) {
        static_cast<RLEModel*>(ptr)->pop();
    }

}