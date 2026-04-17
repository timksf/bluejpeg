#ifndef __PPM_HPP__
#define __PPM_HPP__

#include <sstream>
#include <vector>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <ranges>

#include "bmp.hpp"

namespace ppm {

    //conversion from BMP to PPM pixel layout
    std::vector<rgb_t> bmp2ppm_pixels(bmp_image img){
        //conversion pipeline
        auto flipped_vert = img.pixels() 
            | std::ranges::views::reverse                   //reverse pixels in effort to swap rows
            | std::ranges::views::chunk(img.width())        //split into rows
            | std::views::transform(std::views::reverse)    //bring rows into correct order by reversal    
            | std::ranges::views::join;                     //join rows(chunks) into same view again
        std::vector<rgb_t> ppm_img;
        ppm_img.reserve(img.width()*img.height());
        std::ranges::copy(flipped_vert, std::back_inserter(ppm_img));
        return ppm_img;
    }

    template<std::ranges::input_range Range>
        requires (
            std::same_as<std::ranges::range_value_t<Range>, rgb_t> &&
            std::ranges::sized_range<Range>
        )
    bool write_to_file(
        const std::string &filename,
        Range &&values,
        uint32_t width,
        uint32_t height,
        bool binary
    ) {
        std::ofstream f(filename, std::ios::out | std::ios::trunc);
        if(!f.is_open()){
            std::cerr << "Failed to open file " << filename << std::endl;
            return false;
        }
        auto pixels = std::ranges::size(values);
        if(pixels != width*height){
            std::cerr << "pixel amount (" << pixels << ")";
            std::cerr << " does not match width and height (";
            std::cerr << width << "x" << height;
            std::cerr << ")" << std::endl;
            return false;
        }
        //write header in plain ASCII
        f.seekp(0);
        f << (binary ? "P6" : "P3") << std::endl;
        f << std::to_string(width) << " " << std::to_string(height) << std::endl;
        f << "255" << std::endl;
        //now write data
        std::stringstream current_line;
        for(int i = 0; auto &&pix : values){
            if(!binary) {
                if(i > 0 && i % 6 == 0) { //after 6 pixels finish the current line
                    current_line << std::endl;
                    f << current_line.str();
                    current_line.clear();
                }
                current_line << std::setw(3) << (int)pix.r << " ";
                current_line << std::setw(3) << (int)pix.g << " ";
                current_line << std::setw(3) << (int)pix.b << " ";
            } else {
                f << pix.r << pix.g << pix.b;
            }
        }
        if(!binary) {
            if(pixels % 6 != 0){ //write tail
                current_line << std::endl;
                f << current_line.str();
            }
        }
        f.flush();
        f.close();
        return true;
    }

}

#endif //__PPM_HPP__