#include <iostream>
#include <cstdlib>
#include <vector>

#include "simplehuffman.hpp"
#include "jpeghuffman.hpp"

void test_simple() {
    using namespace std;
    string message = "A_DEAD_DAD_CEDED_A_BAD_BABE_A_BEADED_ABACA_BED";
    message = "Huffman coding is a data compression algorithm.";
    vector<char> symbols{ message.begin(), message.end() };

    NaiveHuffmanTree<char> hufftree;
    hufftree.build(symbols);
    hufftree.print_codebook();

    cout << hufftree.encode_str(symbols) << endl; 
    auto code = hufftree.encode(symbols);
    auto dec = hufftree.decode(code);
    string dec_str(dec.begin(), dec.end());
    cout << "Decoded string: " << dec_str << endl;
}

int main(int argc, char **argv){
    // using namespace std;

    // std::vector<int16_t> dcs{ 1, 1, 1, 1048 };
    // int freqs[256] = { };

    // JPEGHuffmanCode::calc_dc_freqs(dcs, freqs, 256);

    // for(auto i = 0; i < 20; i++)
    //     cout << "i=" << i << ": " << freqs[i] << ", " << endl;

    // JPEGHuffmanCode huff(freqs, 256);
    // huff.build();

    // return EXIT_SUCCESS;
}