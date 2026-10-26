#include "Vlz4_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <lz4.h>
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cassert>
#include <cstring>

Vlz4_top* dut;
VerilatedVcdC* trace;
vluint64_t ticks = 0;

struct retret {
    std::vector<char> bytes;
    uint64_t sz;
};

retret ftomem(const std::string& filepath) {
    retret out;
    out.sz = 0;
    std::ifstream file(filepath, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        std::cerr << "ur stupid this file is bad: " << filepath << "\n";
        return out;
    }

    std::streamsize fsize = file.tellg();
    file.seekg(0, std::ios::beg);

    if (fsize <= 0) {
        std::cerr << "bad file bro\n";
        return out;
    }

    out.sz = static_cast<uint64_t>(fsize);
    out.bytes.resize(out.sz);
    if (!file.read(out.bytes.data(), out.sz)) {
        std::cerr << "failed to read into mem\n";
        out.bytes.clear();
        out.sz = 0;
        return out;
    }

    file.close();
    return out;
}

std::vector<char> drive_verilator(const std::string& filepath) {
    // TODO: DRIVE VERILATOR
    return std::vector<char>(1);
}

std::vector<char> decomp(const std::vector<char>& compressed, uint64_t sz) {
    std::vector<char> ret(sz);

    int ret_size = LZ4_decompress_safe(compressed.data(), ret.data(), compressed.size(), sz);
    if (ret_size <= 0) {
        std::cerr << "lz4 decompress failed\n";
        ret.clear();
        return ret;
    }

    ret.resize(ret_size);
    return ret;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cout << "usage: " << argv[0] << " ./test_decompress <fname>\n";
        return 1;
    }
    std::string fname = argv[1];
    retret gt = ftomem(filepath);
    std::vector<char> sim = decomp(drive_verilator(filepath), gt.sz);

    assert(sim.size() == gt.sz);
    int result = memcmp(gt.bytes.data(), sim.data(), gt.sz);
    assert(result == 0);

    return 0;
}