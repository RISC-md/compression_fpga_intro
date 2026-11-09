#include "Vlz4_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <lz4.h>
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstdint>
#include <cstring>
#include <random>

Vlz4_top* dut;
VerilatedVcdC* trace;
vluint64_t ticks = 0;

static uint64_t cycle_budget(size_t n) {
    return 64ull * (uint64_t)n + 10000ull;
}

static int throttle = 0;
static std::mt19937 rng;

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

static void half(int level) {
    dut->clk = level;
    dut->eval();
    if (trace) trace->dump(ticks++);
}

static bool maybe_stall() {
    return throttle > 0 && (int)(rng() % (unsigned)throttle) == 0;
}

static void reset_dut() {
    dut->rst_n     = 0;
    dut->in_valid  = 0;
    dut->in_data   = 0;
    dut->in_last   = 0;
    dut->out_ready = 0;
    for (int i = 0; i < 4; i++) {
        half(0);
        half(1);
    }
    dut->rst_n = 1;
}

std::vector<char> drive_verilator(const std::vector<char>& input) {
    std::vector<char> out;

    reset_dut();

    size_t i = 0;
    bool done = false;
    uint64_t cycles = 0;
    const uint64_t budget = cycle_budget(input.size());

    while (!done && cycles < budget) {
        cycles++;

        bool have = (i < input.size());
        bool offer = have && !maybe_stall();

        dut->in_valid  = offer;
        dut->in_data   = offer ? (uint8_t)input[i] : 0;
        dut->in_last   = offer && (i + 1 == input.size());
        dut->out_ready = !maybe_stall();

        half(0);
        bool acc = dut->in_valid && dut->in_ready;
        bool got = dut->out_valid && dut->out_ready;
        uint8_t ob = dut->out_data;
        bool olast = dut->out_last;
        half(1);

        if (acc) i++;
        if (got) {
            out.push_back((char)ob);
            if (olast) done = true;
        }
    }

    dut->in_valid  = 0;
    dut->out_ready = 0;

    if (!done) {
        std::cerr << "  TIMEOUT after " << cycles << " cycles"
                  << " (fed " << i << "/" << input.size() << " bytes,"
                  << " got " << out.size() << " out)\n";
        out.clear();
    }
    return out;
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

static bool run_case(const std::string& name, const std::vector<char>& input) {
    std::cout << "[" << name << "] " << input.size() << " bytes in";
    if (throttle) std::cout << " (throttle 1/" << throttle << ")";
    std::cout << "\n";

    std::vector<char> comp = drive_verilator(input);
    if (comp.empty()) {
        std::cout << "  FAIL: no output\n";
        return false;
    }

    std::cout << "  " << comp.size() << " bytes out ("
              << (100.0 * (double)comp.size() / (double)input.size()) << "%)\n";

    std::vector<char> back = decomp(comp, input.size());
    if (back.empty()) {
        std::cout << "  FAIL: malformed block, liblz4 rejected it\n";
        return false;
    }
    if (back.size() != input.size()) {
        std::cout << "  FAIL: decompressed to " << back.size()
                  << " bytes, expected " << input.size() << "\n";
        return false;
    }
    if (memcmp(back.data(), input.data(), input.size()) != 0) {
        size_t at = 0;
        while (at < input.size() && back[at] == input[at]) at++;
        std::cout << "  FAIL: well-formed but wrong, first mismatch at byte " << at
                  << " (got " << std::hex << (int)(uint8_t)back[at]
                  << ", expected " << (int)(uint8_t)input[at] << std::dec << ")\n";
        return false;
    }

    std::cout << "  PASS\n";
    return true;
}

static std::vector<char> pat_const(size_t n, char c) {
    return std::vector<char>(n, c);
}

static std::vector<char> pat_random(size_t n, uint32_t seed) {
    std::mt19937 r(seed);
    std::vector<char> v(n);
    for (size_t i = 0; i < n; i++) v[i] = (char)(r() & 0xFF);
    return v;
}

static std::vector<char> pat_cycle(size_t n, const std::string& unit) {
    std::vector<char> v(n);
    for (size_t i = 0; i < n; i++) v[i] = unit[i % unit.size()];
    return v;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Verilated::traceEverOn(true);

    dut = new Vlz4_top;
    trace = new VerilatedVcdC;
    dut->trace(trace, 99);
    trace->open("dump.vcd");

    int failed = 0;
    int total = 0;

    struct Case {
        std::string name;
        std::vector<char> data;
    };
    std::vector<Case> cases;

    cases.push_back({"one byte", pat_const(1, 'x')});
    cases.push_back({"mflimit-1", pat_const(11, 'x')});
    cases.push_back({"mflimit", pat_const(12, 'x')});
    cases.push_back({"mflimit+1", pat_const(13, 'x')});

    cases.push_back({"all same x1000", pat_const(1000, 'A')});

    cases.push_back({"random x1000", pat_random(1000, 12345)});

    cases.push_back({"abc cycle x999", pat_cycle(999, "abc")});

    { // local
        std::vector<char> v = pat_random(500, 999);
        std::vector<char> t = pat_const(500, 'Z');
        v.insert(v.end(), t.begin(), t.end());
        cases.push_back({"random+const", v});
    }

    for (int a = 1; a < argc; a++) {
        if (argv[a][0] == '+' || argv[a][0] == '-') continue;
        retret f = ftomem(argv[a]); // cmdline files
        if (f.sz) cases.push_back({std::string("file ") + argv[a], f.bytes});
    }

    for (int pass = 0; pass < 2; pass++) {
        throttle = pass ? 3 : 0;
        rng.seed(0xC0FFEE + pass);
        std::cout << "=== pass " << (pass + 1) << "/2 "
                  << (pass ? "(throttled)" : "(full rate)") << " ===\n";
        for (size_t c = 0; c < cases.size(); c++) {
            total++;
            if (!run_case(cases[c].name, cases[c].data)) failed++;
        }
    }

    trace->close();
    delete trace;
    delete dut;

    std::cout << "\n" << (total - failed) << "/" << total << " passed\n";
    return failed ? 1 : 0;
}
