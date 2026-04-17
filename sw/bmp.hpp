#ifndef _BMP_HPP_
#define _BMP_HPP_

#include <iostream>
#include <cstdint>
#include <string>
#include <fstream>
#include <vector>
#include <ranges>

#include "util.hpp"

struct bmp_header {
    uint16_t signature;
    uint32_t file_size;
    uint32_t rsvd;
    uint32_t data_offset;
} __attribute__((packed)); //avoid issues with padding

struct bmp_info_header {
    uint32_t infosize;
    uint32_t width;
    uint32_t height;
    uint16_t planes;
    uint16_t bpp;
    uint32_t compression;
    uint32_t image_size;
    uint32_t hres;
    uint32_t vres;
    uint32_t n_colors;
    uint32_t n_important_colors;
} __attribute__((packed));

struct bmp_image {

    bmp_image(std::string filename): _filename(filename) {
    }

    bmp_image(uint32_t width, uint32_t height):
        _width(width),
        _height(height) {
        _pixels.reserve(width * height);
        for(auto i = 0; i < width*height; i++){
            _pixels[i] = { 0, 0, 0 };
        }
    }

    bool set_data(std::vector<uint8_t> data) {
        if(data.size() != _width * _height * 3) return false;
        for(auto i = 0; i < _width*_height*3; i+=3){
            _pixels[i/3] = { data[i], data[i+1], data[i+2] };
        }
        return true;
    }

    bool set_uniform(uint8_t v) {
        for(auto i = 0; i < _width*_height; i++){
            _pixels[i] = { v, v, v };
        }
        return true;
    }

    //set uniform per-pixel
    bool set_uniform_pp(std::vector<uint8_t> data) {
        if(data.size() != _width * _height) return false;
        for(auto i = 0; i < _width*_height; i++){
            auto v = data[i];
            _pixels[i] = { v, v, v };
        }
        return true;
    }

    bool load() {
        std::ifstream f(_filename, std::ios::in | std::ios::binary | std::ios::ate);
        if(f.is_open()){
            auto size = f.tellg();
            f.seekg(0, std::ios::beg);
            bmp_header header;
            bmp_info_header infoheader;
            f.read(reinterpret_cast<char*>(&header), sizeof(header));
            f.read(reinterpret_cast<char*>(&infoheader), sizeof(infoheader));
            char sig1 = static_cast<char>((header.signature >> 8) & 0xFF);
            char sig0 = static_cast<char>(header.signature & 0xFF);
            if(sig1 != 'M' || sig0 != 'B') {
                std::cerr << "BMP signature incorrect, expected \"BM\" got " << sig0 << sig1 << std::endl;
                return false;
            }
            if(infoheader.bpp != 24){
                std::cerr << "Only 24 bit pixel data supported, got " << infoheader.bpp << std::endl;
                return false;
            }
            if(infoheader.compression != 0){
                std::cerr << "BMP compression not supported" << std::endl;
                return false;
            }
            std::cout << "Image format OK" << std::endl;
            std::cout << "Image width: " << infoheader.width << " height: " << infoheader.height << std::endl;
            f.seekg(header.data_offset); //move to pixel data
            //read pixel data
            std::vector<rgb_t> pixels;
            for(auto i = 0; i < infoheader.height; i++){
                for(auto j = 0; j < infoheader.width; j++){
                    //data is stored as BGR not RGB
                    uint8_t b = f.get();
                    uint8_t g = f.get();
                    uint8_t r = f.get();
                    pixels.emplace_back(r, g, b);
                }
                f.seekg(infoheader.width % 4, std::ios::cur);
            }
            _pixels = pixels;
            _width = infoheader.width;
            _height = infoheader.height;
            f.close();
            std::cout << "Successfully read " << size << " bytes" << std::endl;
        } else {
            std::cerr << "Failed to open file " << _filename << std::endl;
            return false;
        }
        return true;
    }

    void store(std::string filename) {
        uint32_t data_offset = sizeof(bmp_header) + sizeof(bmp_info_header);
        uint32_t fsz = static_cast<uint32_t>(data_offset+(3*_width+_width%4)*_height);
        bmp_header header = {
            signature: ('M' << 8) | 'B',
            file_size: fsz,
            rsvd: 0,
            data_offset: data_offset
        };
        bmp_info_header infoheader{
            infosize: sizeof(bmp_info_header),
            width: _width,
            height: _height,
            planes: 1,
            bpp: 24,
            compression: 0,
            image_size: 0,
            hres: 0,
            vres: 0,
            n_colors: 0,
            n_important_colors: 0
        };
        std::ofstream f(filename, std::ios::out | std::ios::binary);
        f.write(reinterpret_cast<char*>(&header), sizeof(header));
        f.write(reinterpret_cast<char*>(&infoheader), sizeof(infoheader));
        for(auto i = 0; i < _height; i++) {
            for(auto j = 0; j < _width; j++){
                //note: order ist BGR not RGB
                f.put(_pixels[i*_width+j].b);
                f.put(_pixels[i*_width+j].g);
                f.put(_pixels[i*_width+j].r);
            }
            for(auto j = 0; j < _width%4; j++) f.put(0); //pad to multiple of 4 bytes
        }
        f.close();
        std::cout << "Stored bmp image as " << filename << std::endl;
    }

    void print_info() {
        std::cout << "bmp_image@" << this << " " << _width << "x" << _height << std::endl;
    }

    rgb_t& at(int x, int y) {
        return _pixels[y*_width+x];
    }

    uint32_t width() const {
        return _width;
    }

    uint32_t height() const {
        return _height;
    }

    auto pixels() const {
        return std::views::all(_pixels);
    }

private:

    uint32_t _height;
    uint32_t _width;
    std::vector<rgb_t> _pixels;
    std::string _filename;
};

#endif // _BMP_HPP_