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

    import lz4_pkg::*;

    localparam logic [LEN_W-1:0] BLOCK_SZ = LEN_W'(1) << BLOCK_LB;
    localparam int IN_DEPTH_LB = 4;
    localparam int OUT_DEPTH_LB = 10;

    typedef enum logic [3:0] {
        S_LOAD, S_CHECK, S_PRIME_ADDR, S_PRIME_CAP, S_SCAN0, S_SCAN1, S_MATCH0, S_MATCH1, S_EM_TOKEN, S_EM_LEN, S_EM_LITS_ADDR, S_EM_LITS_PUSH, S_EM_OFF0, S_EM_OFF1, S_DONE
    } state_t;

    state_t state;
    
    // TODO: the actual encoder lmao

    assign in_ready = 1'b0;
    assign out_valid = 1'b0;
    assign out_data = '0;
    assign out_last = 1'b0;

endmodule

`default_nettype wire

/* verilator lint_on UNUSEDPARAM */
