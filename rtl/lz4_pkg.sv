package lz4_pkg;

    localparam int BLOCK_LB = 16;
    localparam int LEN_W = BLOCK_LB + 1;
    localparam int HASH_LB = 12;
    localparam int MIN_MATCH = 4;
    localparam int LAST_LITS = 5;
    localparam int MF_LIMIT = 12;

    function automatic logic [HASH_LB-1:0] hash4(input logic [31:0] v);
        return HASH_LB'((v * 32'd2654435761) >> (32 - HASH_LB));
    endfunction

endpackage
