#include <cstdint>
#include <fstream>
#include <stdexcept>
#include <vector>

//preserve the top raster rows and BMP storage orientation for the large simulation fixture
extern "C" void prepare_udp_test_image(const char* path, uint8_t large) {
    std::ifstream input(path, std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
    if (bytes.size() < 54 || bytes[0] != 'B' || bytes[1] != 'M')
        throw std::runtime_error("ERROR: invalid UDP test BMP");
    auto read32 = [&](size_t offset) {
        uint32_t value = 0;
        for (unsigned i = 0; i < 4; ++i) value |= uint32_t(bytes.at(offset + i)) << (8 * i);
        return value;
    };
    auto write32 = [&](size_t offset, uint32_t value) {
        for (unsigned i = 0; i < 4; ++i) bytes.at(offset + i) = uint8_t(value >> (8 * i));
    };
    if (large) {
        uint32_t offset = read32(10);
        uint32_t width = read32(18);
        int32_t height = static_cast<int32_t>(read32(22));
        if (width != 1920 || height != 1280 || read32(30) != 0 || bytes[28] != 24)
            throw std::runtime_error("ERROR: expected uncompressed 1920x1280 24-bit BMP");
        uint32_t stride = (width * 3 + 3) & ~3u;
        bytes.erase(bytes.begin() + offset, bytes.begin() + offset + stride * (height - 1080));
        write32(2, static_cast<uint32_t>(bytes.size()));
        write32(22, 1080);
        write32(34, stride * 1080);
    }
    std::ofstream output("udp_test_image.bmp", std::ios::binary);
    output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    if (!output) throw std::runtime_error("ERROR: cannot write UDP test BMP");
}
