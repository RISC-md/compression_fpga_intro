module tb_hash_table;

    import lz4_pkg::*;

    localparam logic [31:0] ABCD = 32'h41424344;

    logic clk;

    logic [31:0] data_in;
    logic [BLOCK_LB-1:0] current_pos;
    logic write_en;

    logic [BLOCK_LB-1:0] previous_pos;

    initial begin 
        clk = 0;
        forever #5 clk = ~clk;
    end

    hash_table dut (
        .clk(clk),
        .data_in(data_in),
        .current_pos(current_pos),
        .write_en(write_en),
        .previous_pos(previous_pos)
    );

    task automatic step(input logic [31:0] d, input logic [BLOCK_LB-1:0] pos, input logic we);
        @(negedge clk);
        data_in     = d;
        current_pos = pos;
        write_en    = we;
        @(posedge clk);
        #1;
    endtask

    initial begin
        data_in     = '0;
        current_pos = '0;
        write_en    = 1'b0;

        step(ABCD, 16'd0, 1'b0);
        step(ABCD, 16'd0, 1'b1); // insert ABCD @0

        step(ABCD, 16'd0, 1'b0); // lookup ABCD
        assert (previous_pos == 16'd0) // should get 0
            else $fatal(1, "lookup after insert: got %0d, expected 0", previous_pos);

        step(ABCD, 16'd6, 1'b1); // insert ABCD @6
        assert (previous_pos == 16'd0) // should still get 0 since that was before we inserted
            else $fatal(1, "insert must return pre-write value: got %0d, expected 0", previous_pos);

        step(ABCD, 16'd6, 1'b0); // read ABCD (lookup)
        assert (previous_pos == 16'd6) // now get 6
            else $fatal(1, "updated lookup: got %0d, expected 6", previous_pos);

        $display("tb_hash_table done.");
        $finish;
    end

endmodule
