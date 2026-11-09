`default_nettype none

module hash_table (
    input  logic clk, // clock for bram stuff

    input  logic [31:0] data_in,
    input  logic [lz4_pkg::BLOCK_LB-1:0] current_pos, // location of data you want to hash in bram
    input  logic write_en, // store current position?

    output logic [lz4_pkg::BLOCK_LB-1:0] previous_pos
);

    import lz4_pkg::*;

    logic [HASH_LB-1:0] addr;
    assign addr = hash4(data_in);

    logic [BLOCK_LB-1:0] tbl [0:(1 << HASH_LB) - 1];

    // no need for reset, the encoder will verify
    // read-first
    always_ff @(posedge clk) begin
        previous_pos <= tbl[addr];
        if (write_en) tbl[addr] <= current_pos;
    end
endmodule

`default_nettype wire
