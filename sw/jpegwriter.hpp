#ifndef __JPEG_WRITER_HPP__
#define __JPEG_WRITER_HPP__

#include <cstdint>
#include <cstdlib>
#include <bitset>
#include <cstring>
#include <vector>
#include <cassert>
#include <ranges>
#include <algorithm>
#include <fstream>
#include <utility>
#include <format>

#include "util.hpp"
#include "jpeg_types.hpp"
#include "jpeghuffman.hpp"

namespace jpegwriter {

    namespace rng = std::ranges;

    constexpr uint8_t DHT[2] = {0xFF, 0xC4}; //define huffman table(s)
    constexpr uint8_t SOI[2] = {0xFF, 0xD8}; //start of image
    constexpr uint8_t EOI[2] = {0xFF, 0xD9}; //end of image
    constexpr uint8_t SOS[2] = {0xFF, 0xDA}; //start of scan
    constexpr uint8_t DQT[2] = {0xFF, 0xDB}; //define quantization table
    constexpr uint8_t COM[2] = {0xFF, 0xFE}; //comment

    constexpr uint8_t SOF0[2] = {0xFF, 0xC0}; //start of frame

    constexpr uint8_t APP0[2] = {0xFF, 0xE0};

    void write_header(byte_ostream &f) {
        f << SOI[0] << SOI[1];
        f << APP0[0] << APP0[1];
        f << 0x00 << 0x10; //header length is 16 + 3*thumbnail_x*thumbnail_y
        f << 'J' << 'F' << 'I' << 'F' << 0; //zero terminated JFIF ID
        f << 0x01 << 0x01; //JFIF version 1.02
        f << 0x0; //density units?
        f << 0x0 << 0x48 << 0x0 << 0x48; //x,y density?
        f << 0x0; //thumbnail size x
        f << 0x0; //thumbnail size y
    }

    template<size_t N> //restricted to byte tables
    void write_quantization_table(byte_ostream &f, std::span<uint8_t, N> qs, uint8_t table_id) {
        uint16_t LEN = N + 1 + 2;
        f << DQT[0] << DQT[1]; //marker
        f << ((LEN>>8)&0xFF) << (LEN&0xFF); //table length is usually 64 bytes for table + 1 ID byte + 2 length bytes
        f << table_id;
        auto scanned = zigzag 
            | std::views::transform([&qs](auto i)->uint8_t&{return qs[i];}); //table has to be written in zigzag scan order
        rng::copy(scanned, byte_ostream_iterator<uint8_t>(f)); //write table, can use raw stream as quantizers are uint8_t
    }

    /*
        table_id: 0 for luma, 1 for chroma
    */
    void write_huffman_table(byte_ostream &f, const JPEGHuffmanCode &huff, uint8_t table_id) {
        uint16_t LEN = 19; //formula on p.41
        for(auto i = 1; i <= 16; i++) 
            LEN += huff.bits(i);
        f << DHT[0] << DHT[1];
        f << ((LEN>>8)&0xFF) << (LEN&0xFF);
        uint8_t table_class = std::to_underlying(huff.category()) << 4;
        f << (table_class | table_id);
        for(auto i = 1; i <= 16; i++)
            f << huff.bits(i);
        //now write huffval with which decoder can reconstruct the codes
        for(auto i = 0; LEN > 19; i++, LEN--)
            f << huff.huffval(i);
    }

    void write_frame_header(byte_ostream &f, size_t width, size_t height, subsampling_t subsampling_mode) {
        uint8_t samplingfactor;
        switch(subsampling_mode) {
            case subsampling_t::YCBCR_444: samplingfactor = 0x11; break; 
            case subsampling_t::YCBCR_422: samplingfactor = 0x21; break;
            case subsampling_t::YCBCR_420: samplingfactor = 0x22; break;
        }
        f << SOF0[0] << SOF0[1];
        f << 0x0 << 17; //length of header 2 for len, 6 info, 3 per channel
        f << 8; //precision for pixels in bits
        f << ((height>>8)&0xFF) << (height&0xFF); //number of lines
        f << ((width>>8)&0xFF) << (width&0xFF); //samples per line
        f << 3; //#components, y,cb,cr
        f << 1; //id 1 for luma, used in scan header
        f << samplingfactor; //sampling factors: {horiz, vert}
        f << 0; //quant table 0 for luma
        f << 2; //id 2 for CB, used in scan header
        f << 0x11;
        f << 1; //quant table 1 shared for chroma
        f << 3; //id 3 for CR, used in scan header
        f << 0x11;
        f << 1; //quant table
    }

    template<rng::input_range InRange>
        requires (
            rng::sized_range<InRange> &&
            rng::random_access_range<InRange>
        )
    void write_scan(
        byte_ostream &f,
        InRange &&dct,
        uint8_t component_id,
        uint8_t dc_table_id,
        uint8_t ac_table_id,
        const JPEGHuffmanCode &huff_dc,
        const JPEGHuffmanCode &huff_ac,
        bool flush = true
    ) {
        f << SOS[0] << SOS[1];
        f << 0x0 << 0x08; //len of scan header
        f << 1; //components in scan
        f << component_id; //scan component selector
        f << ((dc_table_id << 4) | ac_table_id);
        //spectral or predictor selection, not for baseline sequential process
        f << 0x0 << 63; //Ss, Se
        f << 0x0; //unused Ah, Al

        std::stringstream test_bits;
        std::stringstream all_codes;

        /*  Write encoded values
            
            Values are written as entropy coded segment which means they'll 
            be converted to their huffman code and then written to the output file.

            Since the codes are not necessarily 8 bits long, a temporary buffer is needed to
            correctly append the entropy coded values to each other, this is handled inside bit_ostream
            
            There are also some special, implicit AC symbols for EOB and zero run lengths > 15,
            these have to be handled separately
        */
        bit_ostream bitstream { f };
        int consecutive_zeros = 0, last_nonzero = 0;
        for(auto i = 0; i < dct.size(); i++){
            if(i % 64 == 0) { //DC values 
#ifdef DEBUG
                std::cout << std::format("Writing DC value={:d}", dct[i]) << std::endl;
#endif
                codeword_t code = huff_dc.encode_coeff(dct[i]);
                bitstream << code;
                // all_codes << std::format("{:0{}b}", code.second, code.first);
                //after each DC value, check how many trailing zeros are at the end of this MCU
                last_nonzero = i + 63;
                while(last_nonzero > i && dct[last_nonzero] == 0) //move from back to front until nonzero encountered
                    last_nonzero--;
            } else if(i == last_nonzero + 1){ //only zeros remaining, end block with EOB
#ifdef DEBUG
                std::cout << std::format("Writing EOB at {}", i%64) << std::endl;
#endif
                codeword_t EOB = std::make_pair(huff_ac.huffcode(0x00), huff_ac.huffsize(0x00));
                bitstream << EOB;
                i = (i/64+1)*64-1; //move to start of next block
            } else if(dct[i] == 0) { //intermediate zero
                consecutive_zeros++;
                if(consecutive_zeros == 16) {
                    codeword_t ZRL = std::make_pair(huff_ac.huffcode(0xF0), huff_ac.huffsize(0xF0));
                    bitstream << ZRL;
                    consecutive_zeros = 0;
                }
            } else { //ordinary AC value
#ifdef DEBUG
                std::cout << std::format("Writing AC value={:d} with {:d} preceeding zeros", dct[i], consecutive_zeros) << std::endl;
#endif
                codeword_t code = huff_ac.encode_coeff(dct[i], consecutive_zeros);
                bitstream << code;
                consecutive_zeros = 0;
            }
        }
        if(flush) bitstream.flush();
    }

    template<rng::input_range InRange>
        requires (
            rng::sized_range<InRange> &&
            rng::random_access_range<InRange>
        )
    uintmax_t write_jpeg_file(
        const std::string &filename,
        size_t width,
        size_t height,
        InRange &&y_dct,
        InRange &&cb_dct,
        InRange &&cr_dct,
        subsampling_t subsampling_mode,
        std::span<uint8_t, 64> luma_quant,
        std::span<uint8_t, 64> chroma_quant,
        const JPEGHuffmanCode &luma_huff_dc,
        const JPEGHuffmanCode &luma_huff_ac,
        const JPEGHuffmanCode &chroma_huff_dc,
        const JPEGHuffmanCode &chroma_huff_ac
    ) {

        std::ofstream jpeg_file(filename + ".jpg", std::ios::out | std::ios::trunc | std::ios::binary);
        byte_ostream f{ jpeg_file };

        write_header(f);

        write_quantization_table(f, luma_quant, 0); //luma quantizer has table id 0
        write_quantization_table(f, chroma_quant, 1); //chroma quantizer has table id 1

        //the table class is handled inside the function
        write_huffman_table(f, luma_huff_dc, 0x0); //luma huffman tables have id 0
        write_huffman_table(f, luma_huff_ac, 0x0);
        write_huffman_table(f, chroma_huff_dc, 0x1); //chroma huffman tables have id 1
        write_huffman_table(f, chroma_huff_ac, 0x1);

        write_frame_header(f, width, height, subsampling_mode);

        write_scan(f, y_dct, 1, 0, 0, luma_huff_dc, luma_huff_ac);
        std::cout << "Finished writing Y scan" << std::endl;
        write_scan(f, cb_dct, 2, 1, 1, chroma_huff_dc, chroma_huff_ac);
        std::cout << "Finished writing CB scan" << std::endl;
        write_scan(f, cr_dct, 3, 1, 1, chroma_huff_dc, chroma_huff_ac);
        std::cout << "Finished writing CR scan" << std::endl;

        f << EOI[0] << EOI[1];

        jpeg_file.close();

        return f.size();
    }

}
#endif //__JPEG_WRITER_HPP__