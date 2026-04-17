#ifndef __UTIL_HPP__
#define __UTIL_HPP__

#include <ranges>
#include <format>
#include <fstream>
#include <iostream>
#include <cmath>
#include <iterator>
#include <cassert>

#include "jpeg_types.hpp"

/*
    Useful custom concepts
*/

template<typename T>
concept numeric_type = requires(T t) {
    requires std::integral<T> || std::floating_point<T>;
    requires !std::same_as<bool, T>;
    requires !std::is_pointer_v<T>;
};

template<typename T>
concept printable = requires(T t) {
    { std::cout << t } -> std::same_as<std::ostream&>;
};

/*
    Common type definitions
*/

struct rgb_t {
    uint8_t r, g, b;
};

struct ycbcr_t {
    uint8_t y, cb, cr;
};

/*
    Utility functions and classes
*/

template<std::ranges::input_range InRange> requires(std::ranges::sized_range<InRange>)
void print_range_2d_formatted(std::string_view fmt, InRange&& arr, size_t w, size_t h){
    std::cout << "  [span<" << w << "," << h << ">\n";
    for(auto i = 0; i < w*h; i++){
        if(i%w == 0) std::cout << "\t[";
        std::cout << std::vformat(fmt, std::make_format_args(arr[i])) << ", ";
        if(i > 0 && ((i+1) % w == 0)) std::cout << "]" << std::endl;
    }
    std::cout << "  ]";
}

template<std::ranges::input_range InRange> requires(std::ranges::sized_range<InRange>)
void print_range_formatted(std::string_view fmt, InRange&& vs, const char* delim=", ") {
    auto fmtd = vs | std::views::transform([&fmt](const auto& e){
        return std::vformat(fmt, std::make_format_args(e));
    });
    std::ranges::copy(fmtd, std::ostream_iterator<std::string>(std::cout, delim));
}

ycbcr_t rgb2ycbcr(rgb_t rgb) {
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
    return ycbcr;
}

class byte_ostream {
public: 
    byte_ostream(std::ostream &f) : _bytes(0), _stream(f){};
    template<typename T> requires std::convertible_to<T, uint8_t>
    byte_ostream& operator<<(const T &b) {
        _bytes++;
        _stream.put(static_cast<uint8_t>(b));
        return *this;
    }
    std::ostream& raw() {
        return _stream;
    }
    uintmax_t size() {
        return _bytes;
    }
private:
    uintmax_t _bytes;
    std::ostream &_stream;
};

template<typename T>
class byte_ostream_iterator {
public:
    using difference_type = ptrdiff_t;

    byte_ostream_iterator(byte_ostream &stream): _stream(&stream) {
    }

    byte_ostream_iterator &operator=(T v) {
        *_stream << v;
        return *this;
    }

    byte_ostream_iterator& operator*() { return *this; }
    byte_ostream_iterator& operator++() { return *this; }
    byte_ostream_iterator& operator++(int) { return *this; }

private:
    byte_ostream *_stream;
};

class bit_ostream {
public:
    bit_ostream(byte_ostream &f) : _stream(f), _current_bits(0), _buffer(0) {};

    bit_ostream& operator<<(const codeword_t& code){
        auto [bits, len] = code; //extract bits and length from code
        assert(len + _current_bits <= 64 && "Bit code too long");
        _current_bits += len;
        _buffer <<= len;
        _buffer |= (bits.to_ulong() & ((1 << len) - 1));

        while(_current_bits >= 8){ //output all full bytes, starting with "oldest"
            uint8_t out_byte = _buffer >> (_current_bits-8);
#ifdef DEBUG
            std::cout << std::format("output: {:08b} = {:0x}", out_byte, out_byte) << std::endl;
#endif
            _stream << out_byte;
            if(out_byte == 0xFF) {
                _stream << 0x00; //stuffing byte
#ifdef DEBUG
                std::cout << "write stuffing byte" << std::endl;
#endif
            }

            _current_bits -= 8;
        }
        return *this;
    }

    void flush() { 
        if(_current_bits > 0){ //fill last byte with 1's
            *this << std::make_pair(-1, 8-_current_bits);
        }
    }

private:
    uint64_t _buffer;
    size_t _current_bits;
    byte_ostream &_stream;
};

#endif //__UTIL_HPP__