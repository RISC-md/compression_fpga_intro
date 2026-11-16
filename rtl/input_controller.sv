// Accept input bytes through ready/valid, generate block-buffer write addresses,
// and capture the block length when an accepted byte carries in_last.
// Hold the completed block until released, and prevent writes beyond capacity.
