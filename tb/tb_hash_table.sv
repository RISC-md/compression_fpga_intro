`timescale 1ns/1ps

module tb_hash_table;

    logic clk = 0;
    logic rst = 0;

    logic [31:0] data_in;
    logic [15:0] current_pos;
    logic write_en;

    logic [15:0] previous_pos;
    logic valid;

    always #5 clk = ~clk;

    hash_table dut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .current_pos(current_pos),
        .write_en(write_en),
        .previous_pos(previous_pos),
        .valid(valid)
    );

    initial begin

        data_in = 0;
        current_pos = 0;
        write_en = 0;

        rst = 1;
        @(negedge clk);
        rst = 0;

        // inserting ABCD at position 0
        data_in = 32'h41424344;
        current_pos = 0;
        write_en = 1;

        @(posedge clk);
        #1;

        $display("TEST 1: Insert ABCD at position 0");
        $display("Previous: %d, Valid: %b", previous_pos, valid);

        // look up ABCD again
        @(negedge clk);
        current_pos = 6;
        write_en = 0;

        @(posedge clk);
        #1;

        $display("TEST 2: Look up ABCD");
        $display("Previous: %d, Valid: %b", previous_pos, valid);

        // update ABCD to postiojn 6
        @(negedge clk);
        write_en = 1;

        @(posedge clk);
        #1;

        $display("TEST 3: Update ABCD to position 6");
        $display("Previous: %d, Valid: %b", previous_pos, valid);

        // check ts
        @(negedge clk);
        write_en = 0;

        @(posedge clk);
        #1;

        $display("TEST 4: Verify ABCD now points to 6");
        $display("Previous: %d, Valid: %b", previous_pos, valid);

        $finish;
    end

endmodule
