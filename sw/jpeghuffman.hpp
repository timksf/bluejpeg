#ifndef __JEPG_HUFFMAN_HPP__
#define __JEPG_HUFFMAN_HPP__

#include <unordered_map>
#include <cstdint>
#include <cstdlib>
#include <bitset>
#include <cstring>
#include <vector>
#include <cassert>
#include <ranges>
#include <algorithm>
#include <ranges>
#include <span>

#include "util.hpp"
#include "jpeg_types.hpp"

struct JPEGHuffmanCode {
    //allow the printer class to access all private memberes
    friend class JPEGHuffmanPrinter;
private:
    int _codesize[257];             //length of code for symbol i
    size_t _freq[257] = {};         //frequency of symbol i
    int _others[257];               //next element in tree for symbol i
    int _huffval[256] = { -1 };     //symbol indices sorted with ascending codesize
    int _huffsize[256] = { 0 };     //huffman code length of symbol i
    size_t _huffcode[256] = { 0 };  //huffman code for symbol i
    int _bits[33];                  //number of symbols with length i
    JPEGCoeffCategory _category;    //a huffman table is for either DC or AC values
    bool _built;
    bool _uses_predefined_table;

    void reset() {
        std::ranges::fill(_codesize, 0);
        std::ranges::fill(_freq, 0);
        std::ranges::fill(_others, -1);
        std::ranges::fill(_huffval, -1);
        std::ranges::fill(_huffsize, 0);
        std::ranges::fill(_huffcode, 0);
        std::ranges::fill(_bits, 0);
        _built = false;
        _uses_predefined_table = false;
    }

    template<std::signed_integral T>
    static size_t dc_diff_mag(T dc_diff) {
        if(dc_diff == 0) return 0;
        dc_diff = abs(dc_diff);
        size_t r = 0;
        while(dc_diff > 0) {
            dc_diff >>= 1;
            r++;
        }
        return r;
    }

    template<std::signed_integral T>
    static size_t ac_mag(T ac) {
        return dc_diff_mag(ac);
    }

    template<std::ranges::input_range DCTs> requires std::ranges::sized_range<DCTs>
    void calc_dc_freqs(DCTs &&dcts, std::span<size_t, 256> freqs) {
        //could also just provide DCs
        auto dcs = dcts | std::views::stride(64); //DC components are the first value in each 8x8 block
#ifdef DEBUG
        std::cout << "DCs: "; print_range_formatted("{:d}", dcs); std::cout << std::endl;
#endif
        auto it = dcs.begin();
        if(it == dcs.end()) return;

        using T = std::remove_cvref_t<decltype(*it)>;
        T last = *it;
        freqs[dc_diff_mag(last)]++;
        ++it;
        for(; it != dcs.end(); ++it) {
            T current = *it;
            freqs[dc_diff_mag(current - last)]++;
            last = current;
        }
    }

    template<std::ranges::input_range DCTs> 
        requires (
            std::ranges::random_access_range<DCTs> &&
            std::ranges::sized_range<DCTs>
        )
    void calc_ac_freqs(DCTs &&dcts, std::span<size_t, 256> freqs){
        //with a custom drop_every_nth view, just providing the ACs would be possible
        unsigned int consecutive_zeros = 0;
        int last_nonzero = 0; //used for EOBs
        for(auto i = 0; i < dcts.size(); i++){
            if(i % 64 == 0) { //start of ACs for new block
                last_nonzero = i + 63;
                while(last_nonzero > i && dcts[last_nonzero--] == 0); //move from back to front until nonzero encountered
                if(last_nonzero > i) last_nonzero++; //if previous loop ended because of second condition, we move one too far
            } else if(i == last_nonzero + 1){ //now past last nonzero -> end the block as only zeros follow
                freqs[0x00]++; //EOB symbol
                i = (i/64+1)*64-1; //jump ahead to next block
            } else if(dcts[i] == 0){
                consecutive_zeros++;
                if(consecutive_zeros == 16){
                    freqs[0xF0]++;
                    consecutive_zeros = 0;
                }
            } else {
                auto symb = ((consecutive_zeros << 4) & 0xF0) | (ac_mag(dcts[i]) & 0x0F);
                freqs[symb]++;
                consecutive_zeros = 0;
            }
        }
    }

    void calc_codesizes() {
        //K.1 - Procedure to find Huffman code sizes
        //uses symbol frequencies as input
        _freq[256] = 1;
        std::ranges::fill(_codesize, 0);
        std::ranges::fill(_others, -1);
        //build codesize array
        while(1) {
            int v1 = -1;
            int v2 = -1;
            for(auto i = 0; i < 257; i++) {
                if(_freq[i] == 0) continue;
                if(v1 == -1 || _freq[i] <= _freq[v1]) { //find "last" minimum in frequency list
                    v2 = v1;
                    v1 = i;
                } else if(v2 == -1 || _freq[i] <= _freq[v2]) {
                    v2 = i;
                }
            }
            if(v2 == -1) break;
            _freq[v1] += _freq[v2];
            _freq[v2] = 0;
            while(1) {
                _codesize[v1]++;
                if(_others[v1] == -1) break;
                v1 = _others[v1];
            }
            _others[v1] = v2;
            while(1) {
                _codesize[v2]++;
                if(_others[v2] == -1) break;
                v2 = _others[v2];
            }
        }
    }

    void count_sizes() {
        //determines the frequency of each code length
        for(auto i = 0; i < 257; i++) {
            //todo check that no _codesize entry is > 33
            assert(_codesize[i] <= 32);
            if(_codesize[i] != 0)
                _bits[_codesize[i]]++;
        }
    }

    void adjust_bits() {
        //K.3 - Procedure for limiting code lengths to 16 bits
        int i = 31;
        while(1) {
            if(_bits[i] > 0) {
                int j = i - 1;
                do { j--; } while(!(_bits[j] > 0)); //find level with leaf
                _bits[i] -= 2; //remove the two leaves from this level
                _bits[i-1]++; //move one node to previous layer
                _bits[j+1] += 2; //one leaf in j moves to j+1, the other leaf comes from layer i
                _bits[j]--; //remove this moved leaf
            } else {
                i--;
                if(i != 16) continue;
                while(_bits[i--] == 0); //find last level with dummy node
                i++;
                _bits[i]--;
                break; //finish loop after removing dummy node
            }
        }

        std::ranges::fill(_huffval, -1);
        //K.4 sorting procedure, sorts symbols according to required code size
        int k = 0;
        for(int i = 1; i < 32; i++) {
            for(int j = 0; j < 256; j++) {
                if(_codesize[j] == i){
                    _huffval[k++] = j;
                }
            }
        }
    }

    void gen_huffsize() {
        //first determine HUFFSIZEs
        std::ranges::fill(_huffsize, 0);
        int k = 0;
        // Assign each symbol the code length described by the canonical HUFFBITS table.
        for(auto i = 1; i <= 16; i++)
            for(auto j = 0; j < _bits[i]; j++)
                _huffsize[_huffval[k++]] = i;
    }

    void gen_huffcodes() {
        //C.2 canonical code generation directly from HUFFBITS and HUFFVAL.
        std::ranges::fill(_huffcode, 0);
        int k = 0;
        size_t code = 0;
        for(int si = 1; si <= 16; si++) {
            for(int j = 0; j < _bits[si]; j++) {
                _huffcode[_huffval[k++]] = code;
                code++;
            }
            if(si != 16)
                code <<= 1;
        }
    }

    codeword_t encode_dc(int dc_diff) const {
        size_t mag = dc_diff_mag(dc_diff);
        //use magnitude to obtain huffman code
        size_t code = _huffcode[mag];
        int len = _huffsize[mag];
        //now append the "additional bits" mentioned in F.1.2.1.1
        unsigned int id = abs(dc_diff);
        if(dc_diff < 0) id = ~id; //for negative dc_diff append bits of (diff-1)
        code <<= mag;
        code |= (id & ((1 << mag)-1));
        size_t final_len = mag + len;
#ifdef DEBUG
        std::cout << std::format("DC: mag {:x}, class code {:b}, len {}, final {:b}", mag, _huffcode[mag], len, code) << std::endl;
#endif
        std::bitset<MAX_CODE_LEN> bits { code };
        return std::make_pair(bits, final_len);
    }

    codeword_t encode_ac(int ac, int preceeding_zeros) const {
        /*
            F.1.2.2.1
            ac values are encoded as RRRRSSSS
            where RRRR is for the run length of zeros before the coeff.
            and SSSS defines a category for the amplitude denoted by the coeff.
            This symbol is used as index to the huffman table.
        */
        size_t mag = ac_mag(ac);
        auto symb = ((preceeding_zeros << 4) & 0xF0) | (mag & 0x0F);
        auto code = _huffcode[symb];
        auto len = _huffsize[symb];
        unsigned int id = abs(ac);
        if(ac < 0) id = ~id;
        code <<= mag;
        code |= (id & ((1 << mag) - 1));
        size_t final_len = mag + len;
#ifdef DEBUG
        std::cout << std::format("AC: symb {:02x}, class code {:b}, len {}, final {:b}", symb, _huffcode[symb], len, code) << std::endl;
#endif
        std::bitset<MAX_CODE_LEN> bits { code };
        return std::make_pair(bits, final_len);
    }

public:

    JPEGHuffmanCode(): _built(false), _uses_predefined_table(false) {
        reset();
    };

    template<std::ranges::input_range Coeffs>
    void init_from_coeffs(Coeffs &&coeffs, JPEGCoeffCategory cat){
        assert(coeffs.size() % 64 == 0 && "#DCTs should be a multiple of 64");
        reset();
        _category = cat;
        switch(_category){
            case JPEGCoeffCategory::DC: {
                std::span<size_t, 256> f{ _freq, 256 };
                calc_dc_freqs(coeffs, f);
            } break;
            case JPEGCoeffCategory::AC: {
                std::span<size_t, 256> f{ _freq, 256 };
                calc_ac_freqs(coeffs, f);
            } break;
        }
    }

    template<std::ranges::input_range Bits, std::ranges::input_range Huffvals>
        requires (
            std::ranges::sized_range<Bits> &&
            std::ranges::sized_range<Huffvals>
        )
    void init_from_huffvals(Bits &&bits, Huffvals &&huffvals, JPEGCoeffCategory cat) {
        reset();
        _category = cat;

        assert(std::ranges::size(bits) == 16 && "HUFFBITS must contain 16 code-length counts");

        size_t symbol_count = 0;
        size_t bits_idx = 1;
        for(auto bit_count : bits) {
            assert(bit_count >= 0 && "HUFFBITS entries must be non-negative");
            _bits[bits_idx++] = static_cast<int>(bit_count);
            symbol_count += static_cast<size_t>(bit_count);
        }

        assert(symbol_count <= 256 && "HUFFBITS describe too many symbols");
        assert(symbol_count == std::ranges::size(huffvals) && "HUFFVAL count must equal the sum of HUFFBITS");

        size_t val_idx = 0;
        for(auto symbol : huffvals) {
            assert(0 <= symbol && symbol <= 255 && "HUFFVAL symbols must fit into one byte");
            _huffval[val_idx++] = static_cast<int>(symbol);
        }

        _uses_predefined_table = true;
    }

    void build_table() {
        if(!_uses_predefined_table) {
            calc_codesizes();
            std::ranges::fill(_bits, 0);
            count_sizes();
            adjust_bits();
        }
        //now create codes according to annex C
        gen_huffsize();
        gen_huffcodes();
        _built = true;
    }

    codeword_t encode_coeff(int coeff, int consecutive_zeros=0) const {
        if(_built)
            switch(_category){
                case JPEGCoeffCategory::DC:
                    return encode_dc(coeff);
                case JPEGCoeffCategory::AC:
                    return encode_ac(coeff, consecutive_zeros);
            }
        else {
            std::cerr << "Tried to encode value with uninitialized huffman table" << std::endl;
        }
        exit(1);
    }

    JPEGCoeffCategory category() const {
        return _category;
    }

    int bits(size_t i) const {
        assert(0 <= i && i <= 16 && "access of bits array only makes sense in range 0..16");
        return _bits[i];
    }

    int huffval(size_t i) const {
        assert(0 <= i && i <= 255 && "tried to access huffval out of bounds");
        return _huffval[i];
    }

    size_t huffcode(size_t i) const {
        assert(0 <= i && i <= 255 && "tried to access huffcode out of bounds");
        return _huffcode[i];
    }

    int huffsize(size_t i) const {
        assert(0 <= i && i <= 255 && "tried to access huffsize out of bounds");
        return _huffsize[i];
    }

    template<std::ranges::input_range DCs> requires std::ranges::sized_range<DCs>
    static auto dc_diff(DCs&& dcs){
        using T = std::ranges::range_value_t<DCs>;
        T last = *dcs.begin();
        std::ranges::for_each(dcs | std::views::drop(1), [&last](auto &v){
            T tmp = v;
            v -= last;
            last = tmp;
        });
        return dcs;
    }

};

class JPEGHuffmanPrinter {
public:
    static void print_symbol_freqs(
        const JPEGHuffmanCode &luma_dc, 
        const JPEGHuffmanCode &luma_ac,
        const JPEGHuffmanCode &chroma_dc,
        const JPEGHuffmanCode &chroma_ac
    ) {
        std::cout << std::format("{:*<{}s}{:s}{:*<{}s}", "", 3, "Symbol Frequencies", "", 3) << std::endl;
        std::cout << "Code   Luma-DC   Luma-AC   Chroma-DC   Chroma-AC" << std::endl;
        auto zipped = std::views::zip(std::views::iota(0), luma_dc._freq, luma_ac._freq, chroma_dc._freq, chroma_ac._freq);
        for(auto [i, e1, e2, e3, e4] : zipped){
            if(e1 != 0 || e2 != 0 || e3 != 0 || e4 != 0)
                std::cout << std::format("{:4X}{:10d}{:10d}{:12d}{:12d}", i, e1, e2, e3, e4) << std::endl;
        }
    }

    static void print_symbol_lengths(
        const JPEGHuffmanCode &luma_dc, 
        const JPEGHuffmanCode &luma_ac,
        const JPEGHuffmanCode &chroma_dc,
        const JPEGHuffmanCode &chroma_ac
    ) {
        std::cout << std::format("{:*<{}s}{:s}{:*<{}s}", "", 5, "Encoded Symbol Lengths", "", 5) << std::endl;
        std::cout << "Code   Luma-DC   Luma-AC   Chroma-DC   Chroma-AC" << std::endl;
        auto zipped = std::views::zip(std::views::iota(0, 256), luma_dc._codesize, luma_ac._codesize, chroma_dc._codesize, chroma_ac._codesize);
        for(auto [i, e1, e2, e3, e4] : zipped){
            if(e1 != 0 || e2 != 0 || e3 != 0 || e4 != 0)
                std::cout << std::format("{:4X}{:10d}{:10d}{:12d}{:12d}", i, e1, e2, e3, e4) << std::endl;
        }
    }

    static void print_encoded_symb_freqs(
        const JPEGHuffmanCode &luma_dc, 
        const JPEGHuffmanCode &luma_ac,
        const JPEGHuffmanCode &chroma_dc,
        const JPEGHuffmanCode &chroma_ac
    ) {
        std::cout << std::format("{:*<{}s}{:s}{:*<{}s}", "", 5, "Encoded Symbol Frequencies [BITS]", "", 5) << std::endl;
        std::cout << "Length   Luma-DC   Luma-AC   Chroma-DC   Chroma-AC" << std::endl;
        auto zipped = std::views::zip(std::views::iota(0), luma_dc._bits, luma_ac._bits, chroma_dc._bits, chroma_ac._bits);
        for(auto [i, e1, e2, e3, e4] : zipped){
            if(e1 > 0 || e2 > 0 || e3 > 0 || e4 > 0)
                std::cout << std::format("{:6d}{:10d}{:10d}{:12d}{:12d}", i, e1, e2, e3, e4) << std::endl;
        }
    }

    static void print_sorted_code_lengths(
        const JPEGHuffmanCode &luma_dc, 
        const JPEGHuffmanCode &luma_ac,
        const JPEGHuffmanCode &chroma_dc,
        const JPEGHuffmanCode &chroma_ac
    ) {
        std::cout << std::format("{:*<{}s}{:s}{:*<{}s}", "", 5, "Sorted Code Lengths [HUFFVAL, HUFFSIZE]", "", 5) << std::endl;
        std::cout << "Rank    Luma-DC    Luma-AC    Chroma-DC    Chroma-AC" << std::endl;
        auto zipped = std::views::zip(std::views::iota(0, 256), luma_dc._huffval, luma_ac._huffval, chroma_dc._huffval, chroma_ac._huffval);
        for(auto [i, e1, e2, e3, e4] : zipped){
            if(e1 >= 0 || e2 >= 0 || e3 >= 0 || e4 >= 0)
                std::cout << std::format("{:4d}{:8x}{:3d}{:8d}{:3d}{:10d}{:3d}{:10d}{:3d}", i, 
                    e1, e1 == -1 ? 0 : luma_dc._huffsize[e1], 
                    e2, e2 == -1 ? 0 : luma_ac._huffsize[e2], 
                    e3, e3 == -1 ? 0 : chroma_dc._huffsize[e3], 
                    e4, e4 == -1 ? 0 : chroma_ac._huffsize[e4]) << std::endl;
        }
    }

    static void print_sorted_codes(
        const JPEGHuffmanCode &luma_dc, 
        const JPEGHuffmanCode &luma_ac,
        const JPEGHuffmanCode &chroma_dc,
        const JPEGHuffmanCode &chroma_ac
    ) {
        std::cout << std::format("{:*<{}s}{:s}{:*<{}s}", "", 5, "Sorted Huffman Code Words [HUFFCODE, HUFFSIZE]", "", 5) << std::endl;
        std::cout << "Code             Luma-DC             Luma-AC           Chroma-DC           Chroma-AC" << std::endl;
        auto zipped = std::views::zip(std::views::iota(0, 256), luma_dc._huffcode, luma_ac._huffcode, chroma_dc._huffcode, chroma_ac._huffcode);
        for(auto [i, e1, e2, e3, e4] : zipped){
            if(luma_dc._huffsize[i] || luma_ac._huffsize[i] || chroma_dc._huffsize[i] || chroma_ac._huffsize[i])
                std::cout << std::format("{:4x}{:17b}{:3d}{:17b}{:3d}{:17b}{:3d}{:17b}{:3d}", i, 
                    e1, luma_dc._huffsize[i],
                    e2, luma_ac._huffsize[i], 
                    e3, chroma_dc._huffsize[i],
                    e4, chroma_ac._huffsize[i]) << std::endl;
        }
    }
};

#endif // __JEPG_HUFFMAN_HPP__