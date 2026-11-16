default_nettype none

module block_buffer (
    input logic clk,
    input logic rst_n,

    input logic loading,
    input logic wr_valid,
    output logic wr_ready,
    input lz4_pkg::block_addr_t wr_addr,
    input logic [7:0] wr_data,

    input logic req_valid,
    output logic req_ready,
    input lz4_pkg::block_req_kind_t req_kind,
    input lz4_pkg::block_addr_t req_addr, 
    input lz4_pkg::block_addr_t req_other_addr, 

    output logic resp_valid,
    input logic resp_ready,
    output logic [31:0] resp_key,
    output logic [7:0] resp_byte, 
    output logic [7:0] resp_other_byte
);

    import lz4_pkg::*;

    logic a_we, b_we;
    block_addr_t a_addr, b_addr;
    logic [7:0] a_wdata, b_wdata;
    logic [7:0] a_rdata, b_rdata;

    block_req_kind_t saved_kind;
    block_addr_t saved_addr, saved_other_addr;

    typedef enum logic {
        FIRST_PAIR, SECOND_PAIR
    } key_half_t;

    key_half_t key_half;

    typedef enum logic [1:0] {
        IDLE, ISSUE_READ, CAPTURE_READ, RESPONSE
    } state_t;

    state_t state;

ram #(
    .DATA_W(8),
    .ADDR_W(BLOCK_LB)
) block_ram (
    .clk(clk),

    .a_we(a_we),
    .a_addr(a_addr),
    .a_wdata(a_wdata),
    .a_rdata(a_rdata),

    .b_we(b_we),
    .b_addr(b_addr),
    .b_wdata(b_wdata),
    .b_rdata(b_rdata)
);

always_comb begin:
        a_we = 1'b0;
    b_we = 1'b0;
    a_addr = '0;
    b_addr = '0;
    a_wdata = '0;
    b_wdata = '0;

    wr_ready = rst_n && loading && (state == IDLE);
    req_ready = rst_n && !loading && (state == IDLE);
    resp_valid = rst_n && (state == RESPONSE);

    
end


endmodule

`default_nettype wire
