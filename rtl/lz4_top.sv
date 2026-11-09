/* verilator lint_off UNUSEDPARAM */

`default_nettype none

module lz4_top #(
    parameter int WINDOW_LB = 12,
    parameter int HASH_BITS = 12
) (
    input logic clk,
    input logic rst_n,

    input logic in_valid,
    output logic in_ready,
    input logic [7:0] in_data,
    input logic in_last,

    output logic out_valid,
    input logic out_ready,
    output logic [7:0] out_data,
    output logic out_last
);

    // TODO: the actual encoder lmao

    assign in_ready = 1'b0;
    assign out_valid = 1'b0;
    assign out_data = '0;
    assign out_last = 1'b0;

endmodule

`default_nettype wire

/* verilator lint_on UNUSEDPARAM */
