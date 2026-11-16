/* verilator lint_off UNUSEDPARAM */

package lz4_pkg;

    localparam int BLOCK_LB = 12;
    localparam int LEN_W = BLOCK_LB + 1;

    typedef logic [BLOCK_LB-1:0] block_addr_t; // 0–4095
    typedef logic [LEN_W-1:0] block_len_t;    // Can represent 4096

    localparam block_len_t BLOCK_BYTES = block_len_t'(1) << BLOCK_LB;

    typedef enum logic [1:0] {
        KEY4,
        COMPARE2,
        LITERAL1
    } block_req_kind_t;

    localparam int HASH_LB = 12;
    localparam int MIN_MATCH = 4;
    localparam int LAST_LITS = 5;
    localparam int MF_LIMIT = 12;

    function automatic logic [HASH_LB-1:0] hash4(input logic [31:0] v);
        return HASH_LB'((v * 32'd2654435761) >> (32 - HASH_LB));
    endfunction

endpackage

/* verilator lint_on UNUSEDPARAM */
