`default_nettype none

module lz4_top #(
    parameter int WINDOW_LB = 12,
    parameter int HASH_LB = 12
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


endmodule

`default_nettype wire