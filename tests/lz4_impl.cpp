#include <cstdint>
#include <cstring>

static const uint32_t MAX_BLOCK = 65536;
static const uint32_t HASH_BITS = 12;
static const uint32_t HASH_SIZE = 1u << HASH_BITS;
static const uint32_t MIN_MATCH = 4;
static const uint32_t LAST_LITS = 5;
static const uint32_t MF_LIMIT  = 12;

inline uint32_t read32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

inline uint32_t hash4(uint32_t v) {
    return (v * 2654435761u) >> (32 - HASH_BITS);
}

uint32_t put_length(uint8_t* out, uint32_t op, uint32_t len) {
    while (len >= 255) {
        out[op++] = 255;
        len -= 255;
    }
    out[op++] = (uint8_t)len;
    return op;
}

uint32_t lz4_compress(const uint8_t* in, uint32_t n, uint8_t* out) {
    static uint16_t table[HASH_SIZE];
    memset(table, 0, sizeof(table));

    uint32_t ip = 0;
    uint32_t anchor = 0;
    uint32_t op = 0;

    while (ip + MF_LIMIT <= n) {
        uint32_t h = hash4(read32(in + ip));
        uint32_t cand = table[h];
        table[h] = (uint16_t)ip;

        bool ok = (cand < ip) && (ip - cand <= 65535) && (read32(in + cand) == read32(in + ip));
        if (!ok) {
            ip++;
            continue;
        }

        uint32_t limit = n - LAST_LITS;
        uint32_t mlen = MIN_MATCH;
        while (ip + mlen < limit && in[cand + mlen] == in[ip + mlen]) mlen++;

        uint32_t lit = ip - anchor;
        uint32_t mcode = mlen - MIN_MATCH;

        out[op++] = (uint8_t)(((lit >= 15 ? 15 : lit) << 4) | (mcode >= 15 ? 15 : mcode));

        if (lit >= 15) {
            op = put_length(out, op, lit - 15);
        }

        for (uint32_t i = 0; i < lit; ++i) {
            out[op++] = in[anchor + i];
        }

        uint32_t off = ip - cand;
        out[op++] = (uint8_t)(off & 0xFF);
        out[op++] = (uint8_t)(off >> 8);

        if (mcode >= 15) {
            op = put_length(out, op, mcode - 15);
        }

        ip += mlen;
        anchor = ip;
    }

    uint32_t lit = n - anchor;
    out[op++] = (uint8_t)((lit >= 15 ? 15 : lit) << 4);
    if (lit >= 15) {
        op = put_length(out, op, lit - 15);
    }

    for (uint32_t i = 0; i < lit; ++i) {
        out[op++] = in[anchor + i];
    }

    return op;
}