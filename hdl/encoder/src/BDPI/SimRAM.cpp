#include <fstream>

#include "SimRAM.h"

SimRAM::SimRAM(const uint32_t size, const uint32_t bytes_per_word)
    : m_size(size), m_bytes_per_word(bytes_per_word), m_write_accesses(0), m_read_accesses(0) {
    if(bytes_per_word == 0 || bytes_per_word > 8) {
        std::cerr << "[SimRAM] Invalid bytes_per_word: " << bytes_per_word << " (must be 1-8)" << std::endl;
        exit(1);
    }
}

SimRAM::data_t SimRAM::read_word(SimRAM::addr_t word_addr) {
    if(word_addr >= m_size) {
        std::cerr << "[SimRAM] Tried to read word beyond bounds: " << word_addr  << "/" << (m_size-1) << std::endl;
        exit(1);
    }
    ++m_read_accesses;
    data_t result = 0;
    uint64_t base = word_addr * m_bytes_per_word;
    for(uint32_t i = 0; i < m_bytes_per_word; ++i) {
        auto it = m_data.find(base + i);
        if(it != m_data.end())
            result |= static_cast<data_t>(it->second) << (i * 8);
    }
    return result;
}

void SimRAM::write_word(SimRAM::addr_t word_addr, SimRAM::data_t word) {
    if(word_addr >= m_size) {
        std::cerr << "[SimRAM] Tried to write word beyond bounds: " << word_addr << "/" << (m_size-1) << std::endl;
        exit(1);
    }
    uint64_t base = word_addr * m_bytes_per_word;
    for(uint32_t i = 0; i < m_bytes_per_word; ++i) {
        m_data[base + i] = static_cast<uint8_t>((word >> (i * 8)) & 0xFF);
    }
    ++m_write_accesses;
}

void SimRAM::write_strobe(SimRAM::addr_t word_addr, SimRAM::data_t word, SimRAM::data_t strobe) {
    if(word_addr >= m_size) {
        std::cerr << "[SimRAM] Tried to strobe-write word beyond bounds: " << word_addr << "/" << (m_size-1) << std::endl;
        exit(1);
    }
    uint64_t base = word_addr * m_bytes_per_word;
    for(uint32_t i = 0; i < m_bytes_per_word; ++i) {
        if((strobe >> i) & 1) {
            m_data[base + i] = static_cast<uint8_t>((word >> (i * 8)) & 0xFF);
        }
    }
    ++m_write_accesses;
}

SimRAM::data_t SimRAM::read_byte(SimRAM::addr_t byte_addr) {
    const uint64_t capacity = get_byte_size();
    if(byte_addr >= capacity) {
        std::cerr << "[SimRAM] Tried to read byte beyond bounds: " << byte_addr
                  << "/" << capacity << std::endl;
        exit(1);
    }
    ++m_read_accesses;
    auto it = m_data.find(byte_addr);
    return (it != m_data.end()) ? it->second : 0;
}

void SimRAM::write_byte(SimRAM::addr_t byte_addr, SimRAM::data_t byte_val) {
    const uint64_t capacity = get_byte_size();
    if(byte_addr >= capacity) {
        std::cerr << "[SimRAM] Tried to write byte beyond bounds: " << byte_addr
                  << "/" << capacity << std::endl;
        exit(1);
    }
    m_data[byte_addr] = static_cast<uint8_t>(byte_val & 0xFF);
    ++m_write_accesses;
}

void SimRAM::dump_range(const char *filename, SimRAM::addr_t start_byte_addr, uint64_t byte_count) {
    const uint64_t capacity = get_byte_size();
    if(byte_count > capacity || start_byte_addr > capacity - byte_count) {
        std::cerr << "[SimRAM] Tried to dump byte range beyond bounds: start="
                  << start_byte_addr << ", count=" << byte_count
                  << ", capacity=" << capacity << std::endl;
        exit(1);
    }

    std::ofstream out(filename, std::ios::binary);
    if(!out) {
        std::cerr << "[SimRAM] Could not open dump file: " << filename << std::endl;
        exit(1);
    }

    for(uint64_t i = 0; i < byte_count; ++i) {
        const uint64_t byte_addr = start_byte_addr + i;
        auto it = m_data.find(byte_addr);
        const uint8_t byte = (it != m_data.end()) ? it->second : 0;
        out.put(static_cast<char>(byte));
    }

    if(!out) {
        std::cerr << "[SimRAM] Failed while writing dump file: " << filename << std::endl;
        exit(1);
    }

    std::cout << "[SimRAM] Dumped " << byte_count << " bytes from byte address "
              << start_byte_addr << " to " << filename << std::endl;
}

uint32_t SimRAM::get_size() {
    return m_size;
}

uint64_t SimRAM::get_byte_size() {
    return static_cast<uint64_t>(m_size) * m_bytes_per_word;
}

BSV_ENABLE_PSEUDO_GC(SimRAM)
BSV_WRAP_CONSTRUCTOR(SimRAM, (const uint32_t, size), (const uint32_t, bytes_per_word))
BSV_WRAP_INSTANCE_METHOD(SimRAM, read_word, SimRAM::data_t, (SimRAM::addr_t, word_addr))
BSV_WRAP_INSTANCE_METHOD(SimRAM, write_word, void, (SimRAM::addr_t, addr), (SimRAM::data_t, word))
BSV_WRAP_INSTANCE_METHOD(SimRAM, write_strobe, void, (SimRAM::addr_t, addr), (SimRAM::data_t, word), (SimRAM::data_t, strobe))
BSV_WRAP_INSTANCE_METHOD(SimRAM, read_byte, SimRAM::data_t, (SimRAM::addr_t, byte_addr))
BSV_WRAP_INSTANCE_METHOD(SimRAM, write_byte, void, (SimRAM::addr_t, byte_addr), (SimRAM::data_t, byte_val))
BSV_WRAP_INSTANCE_METHOD(SimRAM, dump_range, void, (const char*, filename), (SimRAM::addr_t, start_byte_addr), (uint64_t, byte_count))
