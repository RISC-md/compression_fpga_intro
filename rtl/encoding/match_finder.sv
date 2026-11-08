`timescale 1ns/1ps


module match_finder #(
    parameter int WINDOW_LB = 12,
    parameter int LEN_W = 16
) (
    input logic clk,
    input logic rst,

    input logic search_valid, // are you looking for a search
    output logic search_ready, // ready to look for a search
    input logic [15:0] current_pos,
    input logic [31:0] current_four_bytes,
    input logic [LEN_W-1:0] max_match_length, 


    output logic compare_req,
    input logic compare_ready
    output logic [15:0] current_read_pos,
    output logic [15:0] candidate_read_pos, 

    input logic compare_valid, // validity of returned bytes
    input logic [7:0] current_byte,
    input logic [7:0] candidate_byte,

    output logic result_valid, //search result is available.
    input logic result_ready, // reciver can accept
    output logic match_found, // take a guess chuckenuts
    output logic [15:0] match_offset, // start pos - candidate pos
    output logic [LEN_W-1:0] match_length 
);

    logic [15:0] current_pos_q;.
    logic [31:0] search_bytes_q;
    logic [LEN_W-1:0] max_length_q;
    logic [15:0] candidate_pos_q;
    logic [LEN_W-1:0] matched_count;
    logic [31:0] distance;
    localparam int unsigned WINDOW_SIZE = 1 << WINDOW_LB;

    typedef enum logic [3:0] {
    IDLE,
    HASH_LOOKUP,
    WAIT_HASH,
    CHECK_CANDIDATE,
    REQUEST_BYTES,
    WAIT_BYTES,
    FINISH_MATCH,
    RESULT
    } state_t;

    state_t state;

    logic hash_request_valid;
    logic hash_request_ready;
    logic hash_response_valid;
    logic hash_valid;
    logic hash_table_full;
    logic [15:0] hash_previous_pos;

    assign search_ready = (state == IDLE) && !rst;

    assign result_valid = (state == RESULT) && !rst;
    assign hash_request_valid = (state == HASH_LOOKUP) && !rst;
    assign distance = {16'b0, current_pos_q} - {16'b0, candidate_pos_q};

    assign compare_req = (state == REQUEST_BYTES) && !rst;
    assign current_read_pos = current_pos_q + 16'(matched_count);
    assign candidate_read_pos = candidate_pos_q + 16'(matched_count);

    hash_table hash_table_inst (
        .clk            (clk),
        .rst            (rst),
        .request_valid  (hash_request_valid),
        .request_ready  (hash_request_ready),
        .data_in        (search_bytes_q),
        .current_pos    (current_pos_q),
        .write_en       (1'b1),
        .response_valid (hash_response_valid),
        .previous_pos   (hash_previous_pos),
        .valid          (hash_valid),
        .table_full     (hash_table_full)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (search_valid && search_ready) begin
                        current_pos_q <= current_pos;
                        search_bytes_q <= current_four_bytes;
                        max_length_q <= max_match_length;

                        state <= HASH_LOOKUP;
                    end
                end

                HASH_LOOKUP: begin
                    if (hash_request_valid && hash_request_ready) begin
                        state <= WAIT_HASH;
                    end
                end

                WAIT_HASH: begin
                    if (hash_response_valid) begin
                        if (hash_valid) begin
                            candidate_pos_q <= hash_previous_pos;
                            state <= CHECK_CANDIDATE;
                        end else begin
                            match_found <= 1'b0;
                            match_offset <= '0;
                            match_length <= '0;
                            state <= RESULT;
                        end
                    end
                end


                CHECK_CANDIDATE: begin

                    if ((candidate_pos_q >= current_pos_q) ||
                        (distance > WINDOW_SIZE) ||
                        (distance > 32'd65535) ||
                        (max_length_q < 4)) begin
                        match_found <= 1'b0;
                        match_offset <= '0;
                        match_length <= '0;
                        state <= RESULT;
                    end else begin
                        matched_count <= '0;
                        state <= REQUEST_BYTES;
                    end
                end



                REQUEST_BYTES: begin
                    if (compare_req && compare_ready) begin
                        state <= WAIT_BYTES;
                    end
                end

                WAIT_BYTES: begin
                    if (compare_valid) begin
                        if (current_byte == candidate_byte) begin
                            matched_count <= matched_count + 1'b1;

                            if ((matched_count + 1'b1) >= max_length_q) begin
                                state <= FINISH_MATCH;
                            end else begin
                                state <= REQUEST_BYTES;
                            end
                        end else begin
                            state <= FINISH_MATCH;
                        end
                    end
                end
                FINISH_MATCH: begin
                    if (matched_count >= 4) begin

                        match_found <= 1'b1;
                        match_offset <= current_pos_q - candidate_pos_q;
                        match_length <= matched_count;

                    end else begin
                        match_found <= 1'b0;
                        match_offset <= '0;
                        match_length <= '0;
                    end


                    state <= RESULT;
                end

                RESULT: begin
                    if (result_valid && result_ready) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end


endmodule
