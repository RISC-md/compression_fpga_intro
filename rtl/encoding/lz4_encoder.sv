// Accept literal/match sequence descriptions and emit LZ4 tokens, extended
// lengths, literal bytes fetched from the block buffer, and little-endian offsets.
// Handle the final literal-only sequence, output backpressure, and final-byte flag.
