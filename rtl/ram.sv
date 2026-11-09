`default_nettype none

module ram #(
    parameter int DATA_W = 8,
    parameter int ADDR_W = 16
) (
    input logic clk,

    input logic a_we,
    input logic [ADDR_W-1:0] a_addr,
    input logic [DATA_W-1:0] a_wdata,
    output logic [DATA_W-1:0] a_rdata,

    input logic b_we,
    input logic [ADDR_W-1:0] b_addr,
    input logic [DATA_W-1:0] b_wdata,
    output logic [DATA_W-1:0] b_rdata
);

    logic [DATA_W-1:0] mem [0:(1 << ADDR_W) - 1];

    always_ff @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_wdata;
        a_rdata <= mem[a_addr];
    end

    always_ff @(posedge clk) begin
        if (b_we) mem[b_addr] <= b_wdata;
        b_rdata <= mem[b_addr];
    end

    `ifndef SYNTHESIS // SIM ONLY
        always_ff @(posedge clk) begin
            if ((a_we || b_we) && a_addr == b_addr && (a_we != b_we || (a_we && b_we)))
            $error("ram: cross-port same-address access at %h (a_we=%b b_we=%b)", a_addr, a_we, b_we);
        end
    `endif

endmodule

`default_nettype wire
