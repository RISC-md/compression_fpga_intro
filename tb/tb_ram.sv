module tb_ram;

    localparam int DW = 8;
    localparam int AW = 4;

    logic clk;
    logic a_we, b_we;
    logic [AW-1:0] a_addr, b_addr;
    logic [DW-1:0] a_wdata, b_wdata, a_rdata, b_rdata;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    ram #(.DATA_W(DW), .ADDR_W(AW)) dut (
        .clk(clk),
        .a_we(a_we), .a_addr(a_addr), .a_wdata(a_wdata), .a_rdata(a_rdata),
        .b_we(b_we), .b_addr(b_addr), .b_wdata(b_wdata), .b_rdata(b_rdata)
    );

    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    initial begin // claude wrote some test cases
                  // tbh not too sure what edge cases to check if adding more
        a_we = 0; a_addr = '0; a_wdata = '0;
        b_we = 0; b_addr = '0; b_wdata = '0;
        tick();

        a_we = 1; a_addr = 4'h3; a_wdata = 8'hAA;  tick(); // ensure that data store and retrieve works
        a_we = 0;                                  tick();
        assert (a_rdata == 8'hAA) else $fatal(1, "write/readback: got %h, expected AA", a_rdata);

        a_we = 1; a_wdata = 8'hBB;                 tick(); // ensure that reading during writing returns old
        assert (a_rdata == 8'hAA) else $fatal(1, "read-first violated: got %h, expected AA", a_rdata);
        a_we = 0;                                  tick(); // then it actually did get written
        assert (a_rdata == 8'hBB) else $fatal(1, "write did not land: got %h, expected BB", a_rdata);

        b_we = 1; b_addr = 4'h9; b_wdata = 8'h99;  tick();
        b_we = 0; a_addr = 4'h9;                   tick(); // prove that the ports can read data the other writes
        assert (a_rdata == 8'h99) else $fatal(1, "B write not seen by A: got %h, expected 99", a_rdata);

        a_we = 1; a_addr = 4'h1; a_wdata = 8'h11;
        b_we = 1; b_addr = 4'h2; b_wdata = 8'h22;  tick(); // we can write from different ports simultaneously
                                                           // as long as it's not the same address
        a_we = 0; b_we = 0;                        tick();
        assert (a_rdata == 8'h11) else $fatal(1, "dual read A: got %h, expected 11", a_rdata);
        assert (b_rdata == 8'h22) else $fatal(1, "dual read B: got %h, expected 22", b_rdata);

        $display("tb_ram done.");
        $finish;
    end

endmodule
