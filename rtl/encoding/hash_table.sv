`timescale 1ns/1ps

module hash_table (
    input  logic clk, // clock for bram stuff
    input  logic rst, // resets validity info

    input  logic [31:0] data_in,
    input  logic [15:0] current_pos, // location of data you want to hash in bram
    input  logic write_en, // store current position?

    output logic [15:0] previous_pos,
    output logic valid // has this position been written before?
);

    logic [11:0] hash_addr;
    logic [4095:0] valid_bits;

    hash_function hash_unit (
        .data_in(data_in),
        .hash_out(hash_addr)
    );

    logic [15:0] tbl [0:4095];

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_bits <= '0;
        end
        else if (write_en) begin
            tbl[hash_addr] <= current_pos;
            valid_bits[hash_addr] <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        previous_pos <= tbl[hash_addr];
        valid <= valid_bits[hash_addr];
    end
endmodule
