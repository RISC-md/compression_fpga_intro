// Wrap byte_fifo.sv with DATA_W=9 to queue each compressed byte and its last flag.
// Propagate backpressure and keep output data and last stable until accepted.
