`timescale 1ns/1ps

module tb_hash_table #(
    parameter int TABLE_LB = 2
);
    localparam int TABLE_SIZE = 1 << TABLE_LB;
    logic clk = 0;
    logic rst = 1;
    logic request_valid = 0;
    logic request_ready;
    logic [31:0] data_in = 0;
    logic [15:0] current_pos = 0;
    logic write_en = 0;
    logic response_valid;
    logic [15:0] previous_pos;
    logic valid;
    logic table_full;
    logic [31:0] collision_keys [0:4];
    int found;

    always #5 clk <= ~clk;

    hash_table #(.TABLE_LB(TABLE_LB)) dut (.*);

    function automatic logic [11:0] hash_key(input logic [31:0] key);
        logic [31:0] product;
        product = key * 32'h9E3779B1;
        return product[31:20];
    endfunction

    task automatic transact(
        input logic [31:0] key,
        input logic [15:0] position,
        input logic do_write,
        input logic expected_valid,
        input logic [15:0] expected_position,
        input logic expected_full
    );
        int cycles;
        @(negedge clk);
        if (!request_ready) $fatal(1, "Table not ready for request");
        data_in = key;
        current_pos = position;
        write_en = do_write;
        request_valid = 1;
        @(posedge clk);
        #1;
        if (request_ready) $fatal(1, "Table did not become busy");
        @(negedge clk);
        // Change all request inputs to verify the accepted request was saved.
        request_valid = 0;
        data_in = ~key;
        current_pos = ~position;
        write_en = ~do_write;
        cycles = 0;
        while (!response_valid) begin
            @(posedge clk);
            #1;
            cycles++;
            if (cycles > 2 * TABLE_SIZE + 2)
                $fatal(1, "Lookup did not terminate");
        end
        if (valid !== expected_valid || previous_pos !== expected_position ||
            table_full !== expected_full)
            $fatal(1, "key=%h got valid=%b pos=%0d full=%b expected %b %0d %b",
                   key, valid, previous_pos, table_full,
                   expected_valid, expected_position, expected_full);
        @(posedge clk);
        #1;
        if (response_valid) $fatal(1, "Response must be a one-cycle pulse");
    endtask

    initial begin
        // Five distinct keys sharing the complete 12-bit hash, at slot 4095.
        // They also wrap at the end of the reduced-size test table.
        found = 0;
        for (int unsigned key = 0; key < 1000000 && found < 5; key++) begin
            if (hash_key(key) == 12'hfff) begin
                collision_keys[found] = key;
                found++;
            end
        end
        if (found != 5) $fatal(1, "Could not generate collision keys");

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;

        transact(collision_keys[0], 0, 0, 0, 0, 0); // Empty read does not insert.
        transact(collision_keys[0], 0, 1, 0, 0, 0);
        transact(collision_keys[0], 0, 0, 1, 0, 0); // Position zero is valid.
        transact(collision_keys[1], 6, 1, 0, 0, 0); // Collision wraps to slot zero.
        transact(collision_keys[2], 12, 1, 0, 0, 0);
        transact(collision_keys[3], 18, 1, 0, 0, 0);
        transact(collision_keys[0], 0, 0, 1, 0, 0);
        transact(collision_keys[1], 0, 0, 1, 6, 0);
        transact(collision_keys[2], 0, 0, 1, 12, 0);
        transact(collision_keys[3], 0, 0, 1, 18, 0);
        transact(collision_keys[1], 24, 1, 1, 6, 0); // Return old position.
        transact(collision_keys[1], 0, 0, 1, 24, 0);
        transact(collision_keys[4], 30, 0, 0, 0, TABLE_SIZE == 4);

        if (TABLE_SIZE == 4) begin
            transact(collision_keys[4], 30, 1, 0, 0, 1); // Full insertion fails.
            transact(collision_keys[0], 0, 0, 1, 0, 0); // No entry was evicted.
            transact(collision_keys[1], 36, 1, 1, 24, 0); // Full table can update.
            transact(collision_keys[1], 0, 0, 1, 36, 0);
        end

        // Reset cancels a request and invalidates all previous entries.
        @(negedge clk);
        request_valid = 1;
        data_in = collision_keys[3];
        write_en = 1;
        @(posedge clk);
        @(negedge clk);
        rst = 1;
        request_valid = 0;
        @(posedge clk);
        #1;
        if (response_valid || request_ready) $fatal(1, "Bad reset behavior");
        @(negedge clk);
        rst = 0;
        transact(collision_keys[3], 0, 0, 0, 0, 0);
        transact(collision_keys[4], 42, 1, 0, 0, 0);
        transact(collision_keys[4], 0, 0, 1, 42, 0);

        $display("PASS: linear probing, TABLE_LB=%0d", TABLE_LB);
        $finish;
    end
endmodule
