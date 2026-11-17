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
        S_LOAD, 
        S_CHECK, 
        S_PRIME_ADDR, 
        S_PRIME_CAP, 
        S_SCAN0, 
        S_SCAN1, 
        S_MATCH0, 
        S_MATCH1, 
        S_EM_TOKEN, 
        S_EM_LEN, 
        S_EM_LITS_ADDR, 
        S_EM_LITS_PUSH, 
        S_EM_OFF0, 
        S_EM_OFF1, 
        S_DONE
    } state_t;

    state_t state;
    
    // TODO: the actual encoder lmao

    logic [LEN_W-1:0] n;
    logic [BLOCK_LB-1:0] ip; //scan pos
    logic [BLOCK_LB-1:0] anchor; //start of run
    logic [BLOCK_LB-1:0] cand;
    logic [BLOCK_LB-1:0] k; // match len counter
    logic [LEN_W-1:0] mlen; // final len to be visible
    logic [31:0] win; // storing ips
    logic [1:0] pc; // prime counter
    logic [7:0] tok;
    logic [LEN_W-1:0] lit; // count of literals
    logic [BLOCK_LB-1:0] lit_base; // anchor for indexing
    logic [BLOCK_LB-1:0] j; // literal emit idx
    logic [LEN_W-1:0] rem; // remaining length
    logic [15:0] off; 
    logic [LEN_W-1:0] mcode; // len - MIN_MATCH
    logic final_seq; // last sequence of the block
    logic len_is_match; // track the run that S_EM_LEN is on
    logic push;
    logic push_last;
    logic [7:0] push_data; // take a fat guess man

    logic [IN_DEPTH_LB:0] ififo_count;
    logic [OUT_DEPTH_LB:0] ofifo_count;
    logic ifx_rd_valid, ifx_rd_ready, ofx_wr_ready;
    logic [8:0] ifx_rd_data, ofx_rd_data;

    byte_fifo #(.DEPTH_LB(IN_DEPTH_LB), .DATA_W(9)) ififo (
        .clk(clk), 
        .rst_n(rst_n),
        .wr_valid(in_valid),
        .wr_ready(in_ready),
        .wr_data({in_last, in_data}),
        .rd_valid(ifx_rd_valid),
        .rd_ready(ifx_rd_ready),
        .rd_data(ifx_rd_data),
        .count(ififo_count)
    );
    wire [7:0] iq_data = ifx_rd_data[7:0];
    wire iq_last = ifx_rd_data[8];

    byte_fifo #(.DEPTH_LB(OUT_DEPTH_LB), .DATA_W(9)) ofifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_valid(push),
        .wr_ready(ofx_wr_ready),
        .wr_data({push_last, push_data}),
        .rd_valid(out_valid),
        .rd_ready(out_ready),
        .rd_data(ofx_rd_data),
        .count(ofifo_count)
    )

    assign out_data = ofx_rd_data[7:0];
    assign out_last = ofx_rd_data[8];

    logic a_we;
    logic [BLOCK_LB-1:0] a_addr, b_addr;
    logic [7:0] a_wdata, a_rdata, b_rdata;

    ram #(.DATA_W(8), .ADDR_W(BLOCK_LB)) blk (
        .clk(clk),
        .a_we(a_we),
        .a_addr(a_addr),
        .a_wdata(a_wdata),
        .a_rdata(a_rdata),
        .b_we(1'b0),
        .b_addr(b_addr),
        .b_wdata(8'h00),
        .b_rdata(b_rdata)
    );

    logic [BLOCK_LB-1:0] ht_prev;
    hash_table ht (
        .clk(clk),
        .data_in(win),
        .current_pos(ip),
        .write_en(state == S_SCAN0),
        .previous_pos(ht_prev)
    )

    wire [LEN_W-1:0] ip_ext = {1'b0, ip};
    wire [LEN_W-1:0] j_ext = {1'b0, j};
    wire [LEN_W-1:0] anchor_ext = {1'b0, anchor};
    wire [LEN_W-1:0] k_ext = {1'b0, k};

    wire need_flush = (ip_ext + LEN_W'(MF_LIMIT)) > n; // are we in last MF_LIMIT bytes?
    wire [LEN_W-1:0] match_limit = n - LEN_W'(LAST_LITS); // stop at LAST_LITS
    wire [LEN+W-1:0] final_lit = n - anchor_ext; // ct for final lits sequence

    function automatic logic [7:0] make_token(
        input logic [LEN_W-1:0] l,
        input logic [LEN_W-1:0] m
    );
        logic [3:0] hi, lo;
        hi = (l >= LEN_W'(15)) ? 4'd15 : l[3:0]; // RIPPED FROM LZ4 DOCUMENTATION PAPER
        lo = (m >= LEN_W'(15)) ? 4'd15 : m[3:0]; // LZ4 TOKEN IS LITERAL COUNT, MATCH LENGTH CODE
        return {hi, lo};
    endfunction

    wire state_t after_lits = final_seq ? S_DONE : S_EM_OFF0;

    always_comb begin
        a_we = 1'b0; a_addr = '0; a_wdata = '0; b_addr = '0;
        case (state)
            S_LOAD: begin
                a_we = ifx_rd_valid;
                a_addr = n[BLOCK_LB-1:0];
                a_wdata = iq_data;
            end
            S_PRIME_ADDR, S_PRIME_CAP:
                a_addr = ip + {{(BLOCK_LB-2){1'B0}}, pc}; // magic. zero extend pc
            S_EM_LITS_ADDR, S_EM_LITS_PUSH:
                a_addr = lit_base + j;
            S_SCAN0, S_SCAN1:
                a_addr = ip + BLOCK_LB'(4);
            S_MATCH0, S_MATCH1: begin
                a_addr = ip + k;
                b_addr = cand + k;
            end
            default: ;
        endcase
    end

    always_comb begin
        push = 1'b0;
        push_data = '0;
        case (state)
            S_EM_TOKEN: begin
                push = 1'b1;
                push_data = tok;
            end
            S_EM_LEN: begin
                push = 1'b1;
                push_data = (rem >= LEN_W'(255)) ? 8'd255 : rem[7:0];
            end
            S_EM_LITS_PUSH: begin
                push = 1'b1; 
                push_data = a_rdata;
            end
            S_EM_OFF0: begin
                push = 1'b1;
                push_data = off[7:0]; 
            end
            S_EM_OFF1: begin
                push = 1'b1;
                push_data = off[15:8];
            end
            default: ;
        endcase
    end

    assign push_last = final_seq && (
        (state == S_EM_TOKEN && lit == '0) ||
        (state == S_EM_LITS_PUSH && (j_ext + LEN_W'(1)) == lit)
    );

    wire fire = push && ofx_wr_ready;
    assign ifx_rd_ready = (state == S_LOAD) && (n < BLOCK_SZ);
    wire iq_fire = ifx_rd_valid && ifx_rd_ready;

    

    // PLACEHOLDERS TO ENSURE COMPILATION !!

    assign in_ready = 1'b0;
    assign out_valid = 1'b0;

endmodule

`default_nettype wire

/* verilator lint_on UNUSEDPARAM */
