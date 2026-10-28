`timescale 1ns/1ps

module hash_function (
    input  logic [31:0] data_in, // take a guess
    output logic [11:0] hash_out // take another guess
);

    logic [31:0] product;

    assign product = data_in * 32'h9E3779B1;
    assign hash_out = product[31:20];

endmodule
