`default_nettype none

module hash_function (
    input logic [31:0] data_in,
    output logic [lz4_pkg::HASH_LB-1:0] hash_out
);
    assign hash_out = lz4_pkg::hash4(data_in);
endmodule

`default_nettype wire
