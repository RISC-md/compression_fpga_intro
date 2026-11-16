# FPGA LZ4 compressor

Work in progress. The memory primitives and match-search components are implemented;
`rtl/lz4_top.sv` is still a stub and cannot accept input or produce compressed output.

## Implemented

- Dual-port synchronous, read-first RAM and byte FIFO, with unit tests.
- Shared multiplicative four-byte hash in `rtl/lz4_pkg.sv`, exposed through
  `rtl/encoding/hash_function.sv`.
- Hash table imported from local `main` at `94e88c6`: request/response handshake,
  saved four-byte keys, linear probing, valid bits, reset, and full-table reporting.
  It returns the previous position before updating an existing key.
- Match finder imported from that same revision, with syntax and reset fixes.
  It checks candidate distance, compares bytes through an external memory interface,
  limits match length, and holds results until accepted. Tests exercise matches,
  mismatches, short limits, out-of-window/forward candidates, reset, request stalls,
  and result backpressure.
- C++ reference compressor in `tests/lz4_impl.cpp` (not linked into the RTL test).
- End-to-end Verilator harness that decompresses hardware output using liblz4 and
  checks the original bytes, at full rate and with randomized stalls.

## Checks

Requires Verilator, a C++ compiler, and liblz4 development headers/library for the
end-to-end harness.

```sh
make test-hash                 # Small and production-size hash tables
make lint-match                # Match finder and its hash dependencies
make tb TB=tb_match_finder
make tb TB=tb_ram
make tb TB=tb_byte_fifo
```

`make lint` and `make test` still encounter unused-signal warnings in the unfinished
top-level module. Even with those warnings disabled, it cannot compress data yet.

## Remaining work

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the implementation order
and the responsibilities of the comment-only RTL stubs.

1. Implement block loading, input/history storage, four-byte reads, and the memory
   adapter for the match finder's compare request/response interface. The current
   match finder expects a response after request acceptance, not on the same edge.
2. Implement scan/anchor control and calculate match limits so the final literals
   and match-start positions meet LZ4 block constraints.
3. Implement sequence encoding: tokens, extended lengths, literals, two-byte offsets,
   and the final literal sequence.
4. Wire the modules into `lz4_top`, including reset, block boundaries, input/output
   backpressure, and `out_last`. Align its package-based 4 KiB block settings with
   the match finder's 16-bit position and length interface.
5. Pass the liblz4 round-trip suite, then add block-size boundary and consecutive
   block coverage. The current harness resets between cases and has no empty-block
   input protocol.
6. Synthesize for the target FPGA and measure BRAM use, timing, throughput, and
   compression ratio.

The probing hash table stops inserting new keys when full; it does not evict old
keys. Probe latency and stale candidates may reduce throughput or compression ratio
and should be evaluated once the compressor runs end to end.
