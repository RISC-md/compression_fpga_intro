# Implementation order

Start with one block at a time: load the complete input, compress it, drain the
output, then accept the next block. Reuse the existing RAM, FIFO, hash table, and
match finder; the new RTL files contain comments only for you to implement.

1. **Agree on interfaces using `rtl/lz4_pkg.sv`.** Keep the first version at a
   maximum of 4096 input bytes, with `in_last` marking the block's final byte.
   Positions need 12 bits within that block; the byte count needs 13 bits to
   represent 4096. Explicitly adapt these to the match finder's 16-bit ports.
   Use ready/valid for requests and results, synchronous memory reads, and at
   most one outstanding memory request. Decide how oversized inputs are handled;
   do not silently split one raw LZ4 block into multiple blocks. Empty input
   requires a separate convention because the current interface has no
   zero-byte transaction.

2. **Implement `rtl/block_buffer.sv`.** Wrap `ram.sv` to store the block and serve
   reads for four-byte search keys, pairs of comparison bytes, and encoder
   literals. Assemble the four-byte key in the same byte order as `read32` in
   `tests/lz4_impl.cpp`. Multiple cycles per request are fine. Check write/read
   correctness, the final address, and read latency before proceeding.

3. **Implement `rtl/input_controller.sv`.** Accept bytes only on a handshake,
   generate write addresses, and capture the length when an accepted byte has
   `in_last`. Hold the completed block available until compression finishes;
   stop accepting input while it is in use. Check one-byte and 4096-byte blocks,
   input stalls, and resetting partway through a load.

4. **Implement `rtl/encoding/lz4_encoder.sv`.** Give it a sequence description:
   literal start/count, whether a match follows, offset, match length, and whether
   this is the final sequence. Have it fetch literal bytes from the block buffer
   and emit the token, literal-length extension, literals, little-endian offset,
   and match-length extension in that order. Emit a literal-only final sequence
   and mark its final output byte. First verify literal-only sequences, then
   matches, length-extension boundaries (including a zero extension byte when
   required), and output stalls.

5. **Implement `rtl/output_buffer.sv`.** Wrap `byte_fifo.sv` with `DATA_W=9` to
   queue each byte together with its last-byte flag. Forward backpressure to the
   encoder and hold the output byte and flag steady until accepted. Check FIFO
   full/empty behavior and a stalled final byte.

6. **Implement `rtl/sequence_controller.sv`.** Track the scan position and the
   anchor of pending literals. Request a four-byte key, submit a match search,
   and forward its memory comparison requests to the block buffer. On a miss,
   advance one byte; on a match, send a sequence to the encoder, wait until it
   finishes using the block buffer, then advance by the match length and update
   the anchor. Search only while `position + MF_LIMIT <= block_length`, and cap
   match length at `block_length - LAST_LITS - position` after checking the
   subtraction is safe. Emit the remaining literals at the end. Check short
   blocks, repeated bytes, misses, and matches with intervening literals.

7. **Wire `rtl/lz4_top.sv` and verify the complete path.** Connect the load,
   search, encode, and drain phases; arbitrate block-buffer reads by phase rather
   than overlapping them initially. Convert the top-level active-low reset for
   the match finder's active-high reset, and clear its hash history for every
   new block. Release the block only after the final output handshake. Add each
   new module to `rtl.f` when it has an implementation. Run the existing liblz4
   round-trip suite, then cover maximum block size, length boundaries, and
   consecutive blocks without a global reset. Finally synthesize and measure
   timing, BRAM usage, throughput, and compression ratio.

The match finder expects comparison data after the request-acceptance edge.
Its existing testbench is an example of that timing. The probing hash table can
stop accepting new keys when full; evaluate its performance after correctness.
