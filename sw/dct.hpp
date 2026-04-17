#ifndef __DCT_HPP__
#define __DCT_HPP__

#include <cstdint>
#include <algorithm>
#include <cmath>
#include <iterator>
#include <array>
#include <ranges>
#include <span>
#include <functional>

#include "util.hpp"

namespace dct {

    namespace rng = std::ranges;

    template<typename t, size_t N>
    void dct2d_naive(t* block, t* res) {
        auto alpha = [](float u){
            return (u == 0) ? M_SQRT1_2 : 1.f;
        };
        for(auto u = 0; u < N; u++) { //u is horizontal
            for(auto v = 0; v < N; v++) { //v is vertical
                float sum = 0.f;
                for(auto y = 0; y < N; y++) {
                    for(auto x = 0; x < N; x++) {
                        // sum += ((float) block[y*N+x]) * cos(((2.f*x+1)*u*M_PI)/(2.f*N)) * cos(((2.f*y+1)*v*M_PI)/(2.f*N));
                        sum=sum+(float)block[y*8+x]*cosf(((2.0*x+1)*u*M_PI)/(2*N))*cosf(((2.0*y+1)*v*M_PI)/(2*N));
                    }
                }
                float freq = 1/4.f * alpha(u) * alpha(v) * sum;
                res[v*N+u] = static_cast<t>(freq);
            }
        }
    }

    template<numeric_type T, size_t N>
    void dct2d_fast(std::span<T, N*N> block, std::span<T, N*N> freqs, const std::array<float, N*N> &cosine_lookup) {
        auto alpha = [](int u){
            return (u == 0) ? M_SQRT1_2 : 1.f;
        };
        for(auto u = 0; u < N; u++) {
            for(auto v = 0; v < N; v++) {
                float fac = .25f * alpha(u) * alpha(v);
                float sum = 0.f;
                for(auto y = 0; y < N; y++) {
                    for(auto x = 0; x < N; x++) {
                        sum += ((float) block[y*N+x]) * cosine_lookup[x*N+u] * cosine_lookup[y*N+v];
                    }
                }
                freqs[v*N+u] = fac * sum;
            }
        }
    }

    template<numeric_type T, size_t N>
    void dct1d(std::span<T, N> data, std::span<T, N> freqs) {
        auto alpha = [](int u){
            return (u == 0) ? M_SQRT1_2 : 1.f;
        };
        for(auto u = 0; u < N; u++) {
            float fac = .5f * alpha(u);
            float sum = 0.f;
            for(auto v = 0; v < N; v++) {
                sum += data[v] * cosf(((2.f*v+1)*u*M_PI)/(2.f*N));
            }
            freqs[u] = fac * sum;
        }
    }

    template<numeric_type T, size_t N>
    void dct2d_as_1d(
        std::span<T, N*N> block,
        std::span<T, N*N> freqs,
        std::function<void (std::span<T, N>, std::span<T, N>)> dct1d
    ) {
        auto alpha = [](int u){
            return (u == 0) ? M_SQRT1_2 : 1.f;
        };
        //dct1d for rows
        for(auto y = 0; y < N; y++) {
            dct1d(block.subspan(y*N).template first<N>(), freqs.subspan(y*N).template first<N>());
        }
        //dct1d for columns
        for(auto x = 0; x < N; x++) {
            T in_col[N] = { T() };
            T out_col[N] = { T() };
            rng::copy(freqs | rng::views::drop(x) | rng::views::stride(N), in_col);
            dct1d(in_col, out_col);
            for(auto row = 0; row < N; row++) {
                freqs[row*N+x] = out_col[row];
            }
        }
        // print_range_2d_formatted("{:.4f}", std::span{ freqs }, 8, 8);
    }

    template<numeric_type R, std::floating_point T>
    void dct1d_aan(std::span<R, 8> block, std::span<R, 8> freqs, bool scale=false) {
        const T a1 = cos(M_PI/4.f); //0.707; //cos(pi/4)
        const T a2 = 0.541; //cos(pi/)
        const T a3 = cos(M_PI/4.f); //0.707;
        const T a4 = 1.307;
        const T a5 = 0.383;

        //stage 0
        T b0 = block[0] + block[7];
        T b1 = block[1] + block[6];
        T b2 = block[2] + block[5];
        T b3 = block[3] + block[4];
        T b4 =-block[4] + block[3];
        T b5 =-block[5] + block[2];
        T b6 =-block[6] + block[1];
        T b7 =-block[7] + block[0];

        //stage 1
        T c0 = b0 + b3;
        T c1 = b1 + b2;
        T c2 =-b2 + b1;
        T c3 =-b3 + b0;
        T c4 =-b4 - b5;
        T c5 = b5 + b6;
        T c6 = b6 + b7;
        T c7 = b7;

        //stage 2
        T d0 = c0 + c1;
        T d1 =-c1 + c0;
        T d2 = c2 + c3;
        T d3 = c3;
        T d4 = c4;
        T d5 = c5;
        T d6 = c6;
        T d7 = c7;

        T helper = (d4 + d6) * a5;

        //stage 3
        T e0 = d0;
        T e1 = d1;
        T e2 = d2 * a1;
        T e3 = d3;
        T e4 = -d4 * a2 - helper;
        T e5 = d5 * a3;
        T e6 = d6 * a4 - helper;
        T e7 = d7;

        //stage 4
        T f0 = e0; 
        T f1 = e1;
        T f2 = e2 + e3;
        T f3 = e3 - e2;
        T f4 = e4;
        T f5 = e5 + e7;
        T f6 = e6;
        T f7 = e7 - e5;

        //stage 5
        T g0 = f0;
        T g1 = f1;
        T g2 = f2;
        T g3 = f3; 
        T g4 = f4 + f7;
        T g5 = f5 + f6;
        T g6 =-f6 + f5;
        T g7 = f7 - f4;

        //values have to be scaled if the scaling factors are not absorbed into the quantization step
        T s0 = !scale ? 1. : (cos(0)*sqrt(.5)/2)/(1       );  // 0.353553
        T s1 = !scale ? 1. : (cos(1.*M_PI/16)/2)/(-a5+a4+1);  // 0.254898
        T s2 = !scale ? 1. : (cos(2.*M_PI/16)/2)/(a1+1    );  // 0.270598
        T s3 = !scale ? 1. : (cos(3.*M_PI/16)/2)/(a5+1    );  // 0.300672
        T s4 = !scale ? 1. : s0;  // (cos(4.*M_PI/16)/2)/(1       );
        T s5 = !scale ? 1. : (cos(5.*M_PI/16)/2)/(1-a5    );  // 0.449988
        T s6 = !scale ? 1. : (cos(6.*M_PI/16)/2)/(1-a1    );  // 0.653281
        T s7 = !scale ? 1. : (cos(7.*M_PI/16)/2)/(a5-a4+1 );  // 1.281458

        //scaling with reordering for bit-reversed indexing as in FFT
        freqs[0] = g0 * s0;
        freqs[4] = g1 * s4;
        freqs[2] = g2 * s2;
        freqs[6] = g3 * s6;
        freqs[5] = g4 * s5;
        freqs[1] = g5 * s1;
        freqs[7] = g6 * s7;
        freqs[3] = g7 * s3;
    }

    template<numeric_type R, std::floating_point T>
    void dct1d_aan_unscaled(std::span<R, 8> block, std::span<R, 8> freqs) {
        //"unscaled" means the results do not have to be scaled again
        return dct1d_aan<R, T>(block, freqs, true);
    }


    /* Inverse DCT implementations */

    template<typename t>
    void idct2d_8x8(t* dcts, t* reconstructed) {
        auto alpha = [](int u){
            return (u == 0) ? 1.f/sqrtf(2.f) : 1.f;
        };
        for(auto y = 0; y < 8; y++) {
            for(auto x = 0; x < 8; x++) {
                float sum = 0.f;
                for(auto u = 0; u < 8; u++) {
                    for(auto v = 0; v < 8; v++) {
                        float fac = alpha(u) * alpha(v);
                        sum += fac * dcts[u*8+v] * cosf(((2*x+1)*u*M_PI)/16.f) * cosf(((2*y+1)*v*M_PI)/16.f);
                    }
                }
                reconstructed[y*8+x] = 0.25f * sum;
            }
        }
    }

}

#endif //__DCT_HPP__