module tb_byte_fifo;

    localparam int DEPTH_LB = 2;
    localparam int DEPTH = 1 << DEPTH_LB;
    localparam logic [DEPTH_LB:0] DEPTH_C = DEPTH[DEPTH_LB:0];

    logic clk, rst_n;
    logic wr_valid, wr_ready;
    logic [7:0] wr_data;
    logic rd_valid, rd_ready;
    logic [7:0] rd_data;
    logic [DEPTH_LB:0] count;

    logic [7:0] got;
    int i;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    byte_fifo #(.DEPTH_LB(DEPTH_LB)) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_data(wr_data),
        .rd_valid(rd_valid), .rd_ready(rd_ready), .rd_data(rd_data),
        .count(count)
    );

    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic push(input logic [7:0] d);
        wr_valid = 1; wr_data = d;
        tick();
        wr_valid = 0;
    endtask

    task automatic pop();
        rd_ready = 1;
        got = rd_data;
        tick();
        rd_ready = 0;
    endtask

    initial begin // claude wrote some test cases here as well
                  // here edge cases are pretty obvious. 
        wr_valid = 0; wr_data = '0; rd_ready = 0;

        rst_n = 0; tick(); tick(); // assert reset works properly (empty state)
        rst_n = 1; tick();
        assert (count == 0)       else $fatal(1, "post-reset count: got %0d, expected 0", count);
        assert (rd_valid == 1'b0) else $fatal(1, "post-reset rd_valid should be 0");
        assert (wr_ready == 1'b1) else $fatal(1, "post-reset wr_ready should be 1");

        push(8'h5A); // assert that push/pop a single byte works
        assert (count == 1)       else $fatal(1, "count after push: got %0d, expected 1", count);
        assert (rd_valid == 1'b1) else $fatal(1, "rd_valid should be 1 with 1 entry");
        pop();
        assert (got == 8'h5A)     else $fatal(1, "round trip: got %h, expected 5A", got);
        assert (count == 0)       else $fatal(1, "count after pop: got %0d, expected 0", count);
        assert (rd_valid == 1'b0) else $fatal(1, "rd_valid should be 0 when empty");

        for (i = 0; i < DEPTH; i++) push(8'hA0 + i[7:0]); // check that edge case of full fifo works
        assert (count == DEPTH_C) else $fatal(1, "count when full: got %0d, expected %0d", count, DEPTH);
        assert (wr_ready == 1'b0) else $fatal(1, "wr_ready should be 0 when full");

        push(8'hFF); // ensure that write is blocked when it is full
        assert (count == DEPTH_C) else $fatal(1, "overflow changed count: got %0d", count);

        for (i = 0; i < DEPTH; i++) begin
            pop(); // ensure that data is removed in order when popping (FIFO)
            assert (got == 8'hA0 + i[7:0])
                else $fatal(1, "drain order at %0d: got %h, expected %h", i, got, 8'hA0 + i[7:0]);
        end
        assert (count == 0)       else $fatal(1, "count after drain: got %0d, expected 0", count);

        pop(); // pop ffrom emtpy doesn't corrupt the fifo
        assert (count == 0)       else $fatal(1, "underflow changed count: got %0d", count);
        push(8'h77);
        pop(); // then push/pop still works
        assert (got == 8'h77)     else $fatal(1, "data after underflow: got %h, expected 77", got);

        for (i = 0; i < DEPTH; i++) push(8'hB0 + i[7:0]); // from a full fifo, does read/write work as expected?
        assert (count == DEPTH_C) else $fatal(1, "refill to full: got %0d", count);
        wr_valid = 1; wr_data = 8'hCC; rd_ready = 1;
        got = rd_data;
        tick();
        wr_valid = 0; rd_ready = 0;
        assert (got == 8'hB0)     else $fatal(1, "head during read+write: got %h, expected B0", got);
        assert (count == DEPTH_C - 1'b1)
            else $fatal(1, "read+write at full: got %0d, expected %0d", count, DEPTH - 1);

        while (rd_valid) pop();
        assert (count == 0)       else $fatal(1, "final drain: got %0d", count);

        for (i = 0; i < 4 * DEPTH + 3; i++) begin // pointers work after cycling
            push(i[7:0]);
            pop();
            assert (got == i[7:0])
                else $fatal(1, "wraparound at %0d: got %h, expected %h", i, got, i[7:0]);
            assert (count == 0)
                else $fatal(1, "wraparound count at %0d: got %0d", i, count);
        end

        $display("tb_byte_fifo done.");
        $finish;
    end

endmodule
