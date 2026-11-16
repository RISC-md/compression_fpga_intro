module tb_match_finder;
    logic clk = 0;
    logic rst = 1;
    logic search_valid = 0, search_ready;
    logic [15:0] current_pos = 0;
    logic [31:0] current_four_bytes = 0;
    logic [15:0] max_match_length = 0;
    logic compare_req, compare_ready = 0;
    logic [15:0] current_read_pos, candidate_read_pos;
    logic compare_valid = 0;
    logic [7:0] current_byte = 0, candidate_byte = 0;
    logic result_valid, result_ready = 0;
    logic match_found;
    logic [15:0] match_offset, match_length;
    logic [7:0] memory [0:65535];
    int cycles;

    initial forever #5 clk = ~clk;
    match_finder dut (.*);

    // Registered memory response with periodic request stalls.
    initial forever begin
        @(negedge clk);
        cycles = cycles + 1;
        compare_valid = 0;
        compare_ready = (cycles % 3 != 0);
        if (compare_req && compare_ready) begin
            current_byte = memory[current_read_pos];
            candidate_byte = memory[candidate_read_pos];
            @(posedge clk);
            @(negedge clk);
            compare_valid = 1;
        end
    end

    task automatic search(
        input logic [15:0] pos,
        input logic [15:0] limit_len,
        input logic expected_found,
        input logic [15:0] expected_offset,
        input logic [15:0] expected_length
    );
        int waited;
        @(negedge clk);
        if (!search_ready) $fatal(1, "Search not ready");
        current_pos = pos;
        current_four_bytes = 32'h41414141;
        max_match_length = limit_len;
        search_valid = 1;
        @(posedge clk);
        @(negedge clk);
        search_valid = 0;
        current_pos = '1;
        current_four_bytes = '1;
        max_match_length = '0;
        waited = 0;
        while (!result_valid) begin
            @(posedge clk);
            #1;
            waited++;
            if (waited > 200) $fatal(1, "Match search timed out");
        end
        repeat (3) begin
            if (!result_valid || match_found !== expected_found ||
                match_offset !== expected_offset || match_length !== expected_length)
                $fatal(1, "pos=%0d got found=%b offset=%0d length=%0d expected %b %0d %0d",
                       pos, match_found, match_offset, match_length,
                       expected_found, expected_offset, expected_length);
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        result_ready = 1;
        @(posedge clk);
        @(negedge clk);
        result_ready = 0;
        if (result_valid || !search_ready) $fatal(1, "Result did not retire");
    endtask

    initial begin
        cycles = 0;
        foreach (memory[i]) memory[i] = 8'h41;
        memory[40] = 8'h42;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;
        search(0, 8, 0, 0, 0);       // First insertion has no candidate.
        search(16, 8, 1, 16, 8);     // Match stops at the caller's limit.
        search(32, 16, 1, 16, 8);    // Match stops at a mismatching byte.
        search(48, 3, 0, 0, 0);      // Fewer than four bytes cannot match.
        search(5000, 8, 0, 0, 0);    // Candidate outside the 4 KiB window.
        search(4990, 8, 0, 0, 0);    // Candidate is ahead of current position.
        @(negedge clk);
        rst = 1;
        @(posedge clk);
        @(negedge clk);
        rst = 0;
        search(16, 8, 0, 0, 0);      // Reset invalidates hash history.
        $display("PASS: match finder limits, mismatch, window, reset, and stalls");
        $finish;
    end
endmodule
