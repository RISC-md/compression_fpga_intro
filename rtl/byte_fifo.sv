`default_nettype none

module byte_fifo #(
    parameter int DEPTH_LB = 10
) (
    input logic clk,
    input logic rst_n,

    input logic wr_valid,
    output logic wr_ready,
    input logic [7:0] wr_data,

    output logic rd_valid,
    input logic rd_ready,
    output logic [7:0] rd_data,

    output logic [DEPTH_LB:0] count // testing ONLY
);

    logic [7:0] mem [0:(1 << DEPTH_LB) - 1];
    logic [DEPTH_LB:0] wr_ptr, rd_ptr;

    wire empty = (wr_ptr == rd_ptr);
    wire full = (wr_ptr[DEPTH_LB] != rd_ptr[DEPTH_LB]) && (wr_ptr[DEPTH_LB-1:0] == rd_ptr[DEPTH_LB-1:0]);

    assign wr_ready = !full;
    assign rd_valid = !empty;
    assign rd_data = mem[rd_ptr[DEPTH_LB-1:0]];
    assign count = wr_ptr - rd_ptr;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (wr_valid && wr_ready) begin
                mem[wr_ptr[DEPTH_LB-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_valid && rd_ready) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
