#include <unordered_map>
#include <iostream>
#include <cstdint>
#include <cstdlib>

#include "bluesy.h"

class SimRAM {
public:

    using data_t = uint64_t;
    using addr_t = uint64_t;

    SimRAM(const uint32_t size, const uint32_t bytes_per_word);
    ~SimRAM(){
        std::cout << "[SimRAM] " << m_write_accesses << " write accesses" << std::endl;
        std::cout << "[SimRAM] " << m_read_accesses << " read accesses" << std::endl;
        std::cout << "[SimRAM] " << m_data.size() << " bytes stored (sparse)" << std::endl;
        std::cout << "[SimRAM] " << "Deconstructing..." << std::endl;
    }

    data_t read_word(addr_t word_addr);
    void write_word(addr_t word_addr, data_t word);
    void write_strobe(addr_t word_addr, data_t word, data_t strobe);

    data_t read_byte(addr_t byte_addr);
    void write_byte(addr_t byte_addr, data_t byte_val);

    uint32_t get_size();

private:
    uint32_t m_size;           // capacity in words
    uint32_t m_bytes_per_word; // configurable word width in bytes (max 8)
    std::unordered_map<uint64_t, uint8_t> m_data;
    uint32_t m_write_accesses;
    uint32_t m_read_accesses;
};

BSV_CONSTRUCTOR_HEADER_DEF(SimRAM, (const uint32_t, size), (const uint32_t, bytes_per_word))