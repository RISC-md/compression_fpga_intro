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
        S_LOAD,         // suck the whole block into ram
        S_CHECK,         // too close to the end to match
        S_PRIME_ADDR,    // ask ram for a window byte
        S_PRIME_CAP,     // byte showed up shift it in
        S_SCAN0,         // insert ip in the hash table
        S_SCAN1,         // candidate is back now decide
        S_MATCH0,        // ask ram for both bytes
        S_MATCH1,        // bytes showed up compare em
        S_EM_TOKEN,      // spit the token
        S_EM_LEN,        // spit 255s for a long length
        S_EM_LITS_ADDR,  // ask ram for a literal
        S_EM_LITS_PUSH,  // literal showed up spit it
        S_EM_OFF0,       // offset low byte
        S_EM_OFF1,       // offset high byte
        S_DONE           // park here til reset
    } state_t;

    state_t state;
    
    // the actual encoder. no longer lmao

    logic [LEN_W-1:0] n;
    logic [BLOCK_LB-1:0] ip; //scan pos
    logic [BLOCK_LB-1:0] anchor; //start of run
    logic [BLOCK_LB-1:0] cand;
    logic [BLOCK_LB-1:0] k; // match len counter
    /* verilator lint_off UNUSEDSIGNAL */
    logic [LEN_W-1:0] mlen; // final len to be visible. nothing reads it
    /* verilator lint_on UNUSEDSIGNAL */
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

    /* verilator lint_off UNUSEDSIGNAL */
    logic [IN_DEPTH_LB:0] ififo_count;  // both counts are waveform only too
    logic [OUT_DEPTH_LB:0] ofifo_count;
    /* verilator lint_on UNUSEDSIGNAL */
    logic ifx_rd_valid, ifx_rd_ready, ofx_wr_ready;
    logic [8:0] ifx_rd_data, ofx_rd_data;

    // 9 bits wide so in_last rides along with its byte
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

    // lets the emitter keep going when the consumer is being slow
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
    );

    assign out_data = ofx_rd_data[7:0];
    assign out_last = ofx_rd_data[8];

    logic a_we;
    logic [BLOCK_LB-1:0] a_addr, b_addr;
    logic [7:0] a_wdata, a_rdata, b_rdata;

    // port a does load writes prime reads literal reads and in[ip+k]
    // port b does window refill and in[cand+k]. never writes anything
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

    logic [BLOCK_LB-1:0] ht_prev; // old guy at this hash. good one cycle after S_SCAN0
    // write_en is just the state. being in S_SCAN0 IS the insert
    hash_table ht (
        .clk(clk),
        .data_in(win),
        .current_pos(ip),
        .write_en(state == S_SCAN0),
        .previous_pos(ht_prev)
    );

    wire [LEN_W-1:0] ip_ext = {1'b0, ip};
    wire [LEN_W-1:0] j_ext = {1'b0, j};
    wire [LEN_W-1:0] anchor_ext = {1'b0, anchor};
    wire [LEN_W-1:0] k_ext = {1'b0, k};

    wire need_flush = (ip_ext + LEN_W'(MF_LIMIT)) > n; // are we in last MF_LIMIT bytes?
    wire [LEN_W-1:0] match_limit = n - LEN_W'(LAST_LITS); // stop at LAST_LITS
    wire [LEN_W-1:0] final_lit = n - anchor_ext; // ct for final lits sequence

    function automatic logic [7:0] make_token(
        input logic [LEN_W-1:0] l,
        input logic [LEN_W-1:0] m
    );
        logic [3:0] hi, lo;
        hi = (l >= LEN_W'(15)) ? 4'd15 : l[3:0]; // RIPPED FROM LZ4 DOCUMENTATION PAPER
        lo = (m >= LEN_W'(15)) ? 4'd15 : m[3:0]; // LZ4 TOKEN IS LITERAL COUNT, MATCH LENGTH CODE
        return {hi, lo};
    endfunction

    wire state_t after_lits = final_seq ? S_DONE : S_EM_OFF0; // last seq just stops

    // who owns the ram ports right now
    // both states of a pair get the same addr or a_rdata lands on the wrong index
    always_comb begin
        a_we = 1'b0; a_addr = '0; a_wdata = '0; b_addr = '0;
        case (state)
            S_LOAD: begin
                a_we = ifx_rd_valid;
                a_addr = n[BLOCK_LB-1:0];
                a_wdata = iq_data;
            end
            S_PRIME_ADDR, S_PRIME_CAP:
                a_addr = ip + {{(BLOCK_LB-2){1'b0}}, pc}; // magic. zero extend pc
            S_EM_LITS_ADDR, S_EM_LITS_PUSH:
                a_addr = lit_base + j;
            S_SCAN0, S_SCAN1:
                b_addr = ip + BLOCK_LB'(4); // port b not port a. this is the window refill
            S_MATCH0, S_MATCH1: begin
                a_addr = ip + k;
                b_addr = cand + k;
            end
            default: ;
        endcase
    end

    // which byte are we spitting this cycle
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

    // last byte of the block. normally the last literal but the token if lit is 0
    assign push_last = final_seq && (
        (state == S_EM_TOKEN && lit == '0) ||
        (state == S_EM_LITS_PUSH && (j_ext + LEN_W'(1)) == lit)
    );

    wire fire = push && ofx_wr_ready; // byte actually left. gate every emit state on this
    assign ifx_rd_ready = (state == S_LOAD) && (n < BLOCK_SZ); // only eat while loading
    wire iq_fire = ifx_rd_valid && ifx_rd_ready; // byte actually came in

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // reset everything or --x-assign unique randomizes it and tests flake
            state <= S_LOAD;
            n <= '0;
            ip <= '0;
            anchor <= '0;
            cand <= '0;
            k <= '0;
            mlen <= '0;
            win <= '0;
            pc <= '0;
            tok <= '0;
            lit <= '0;
            lit_base <= '0;
            j <= '0;
            rem <= '0;
            off <= '0;
            mcode <= '0;
            final_seq <= 1'b0;
            len_is_match <= 1'b0;
        end else begin
            case (state)
                // addr mux is already writing the byte, we just count
                // watch iq_last not in_last, the port is way ahead of the fifo head
                S_LOAD: if (iq_fire) begin
                    n <= n + LEN_W'(1);
                    if (iq_last) state <= S_CHECK;
                end
                // everything that moves ip comes back here so the rule lives in one spot
                S_CHECK: begin
                    if (need_flush) begin // trailing lits then we are done
                        tok <= make_token(final_lit, '0);
                        lit <= final_lit;
                        lit_base <= anchor;
                        rem <= final_lit - LEN_W'(15); // underflow doesn't matter in my design
                        j <= '0;
                        final_seq <= 1'b1;
                        state <= S_EM_TOKEN;
                    end else begin
                        pc <= '0;
                        state <= S_PRIME_ADDR;
                    end
                end
                S_PRIME_ADDR: 
                    state <= S_PRIME_CAP;
                // new byte goes in the top. 4 of em and win[7:0] is in[ip] like read32 wants
                S_PRIME_CAP: begin
                    win <= {a_rdata, win[31:8]};
                    pc <= pc + 2'd1;
                    state <= (pc == 2'd3) ? S_SCAN0 : S_PRIME_ADDR;
                end
                // looks empty but the insert happens just by being here
                S_SCAN0: 
                    state <= S_SCAN1;
                S_SCAN1: begin
                    cand <= ht_prev;
                    // check ht_prev not cand. cand is still last times value
                    // strict less than because offset has to be at least 1
                    if (ht_prev < ip) begin
                        k <= '0;
                        state <= S_MATCH0;
                    end else begin
                        ip <= ip + 1'b1;
                        state <= S_CHECK;
                    end
                end
                S_MATCH0: 
                    state <= S_MATCH1;
                // k is the real match length. started at 0 so no 4 byte verify needed
                // thats also why the hash table can skip valid bits
                S_MATCH1: begin
                    if (a_rdata == b_rdata && (ip_ext + k_ext) < match_limit) begin
                        k <= k + 1'b1;
                        state <= S_MATCH0;
                    end else if (k_ext >= LEN_W'(MIN_MATCH)) begin
                        tok <= make_token(ip_ext - anchor_ext, k_ext - LEN_W'(MIN_MATCH));
                        lit <= ip_ext - anchor_ext;
                        lit_base <= anchor;
                        rem <= (ip_ext - anchor_ext) - LEN_W'(15);
                        j <= '0;
                        off <= 16'(ip - cand);
                        mcode <= k_ext - LEN_W'(MIN_MATCH);
                        mlen <= k_ext;
                        ip <= ip + k;
                        anchor <= ip + k;
                        final_seq <= 1'b0;
                        state <= S_EM_TOKEN;
                    end else begin
                        ip <= ip + 1'b1;
                        state <= S_CHECK; // NEED TO RESET PORT B
                    end
                end
                S_EM_TOKEN: if (fire) begin
                    if (lit >= LEN_W'(15)) begin
                        len_is_match <= 1'b0;
                        state <= S_EM_LEN;
                    end else if (lit != '0)
                        state <= S_EM_LITS_ADDR;
                    else
                        state <= after_lits;
                end
                // same put_length loop for both lengths. len_is_match picks the way out
                S_EM_LEN: if (fire) begin
                    if (rem >= LEN_W'(255))
                        rem <= rem - LEN_W'(255);
                    else if (len_is_match)
                        state <= S_CHECK;
                    else
                        state <= S_EM_LITS_ADDR;
                end
                S_EM_LITS_ADDR: // spits nothing so no fire gate here
                    state <= S_EM_LITS_PUSH;
                S_EM_LITS_PUSH: if (fire) begin
                    j <= j + 1'b1;
                    if ((j_ext + LEN_W'(1)) == lit)
                        state <= after_lits;
                    else
                        state <= S_EM_LITS_ADDR;
                end
                S_EM_OFF0:
                    if (fire) state <= S_EM_OFF1;
                S_EM_OFF1: if (fire) begin
                    if (mcode >= LEN_W'(15)) begin
                        len_is_match <= 1'b1;
                        rem <= mcode - LEN_W'(15);
                        state <= S_EM_LEN;
                    end else begin
                        state <= S_CHECK;
                    end
                end
                S_DONE: ; // nothing left to do
                default: 
                    state <= S_LOAD;
            endcase
        end
    end

    // SIM CHECKS FOR I/O RATE
`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && in_valid && !in_ready)
            $error("lz4_top: input fifo dropped byte %h", in_data);
        if (rst_n && state == S_LOAD && iq_fire && n >= BLOCK_SZ)
            $error("lz4_top: input exceeds a block (%0d bytes)", BLOCK_SZ);
    end
`endif

endmodule

`default_nettype wire

/* verilator lint_on UNUSEDPARAM */
