#ifndef _LITERALS_H_
#define _LITERALS_H_

#include <cstdint>

namespace memsize_literals {

    constexpr std::size_t operator""_KiB(unsigned long long int x) {
        return 1024ULL * x;
    }

    constexpr std::size_t operator""_MiB(unsigned long long int x) {
        return 1024_KiB * x;
    }

    constexpr std::size_t operator""_GiB(unsigned long long int x) {
        return 1024_MiB * x;
    }

}

#endif //_LITERALS_H_