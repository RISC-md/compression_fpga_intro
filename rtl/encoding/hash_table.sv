`timescale 1ns/1ps

module hash_table #(
    parameter int TABLE_LB = 12
) (
    input logic clk,
    input logic rst,

    input logic request_valid,
    output logic request_ready,
    input logic [31:0] data_in,
    input logic [15:0] current_pos,
    input logic write_en,

    output logic response_valid,
    output logic [15:0] previous_pos,
    output logic valid,
    output logic table_full
);
    localparam int TABLE_SIZE = 1 << TABLE_LB;
    typedef enum logic [1:0] {IDLE, READ_SLOT, CHECK_SLOT} state_t;
    state_t state;

    logic [11:0] hash_addr;
    logic [TABLE_SIZE-1:0] valid_bits;
    logic [31:0] keys [0:TABLE_SIZE-1];
    logic [15:0] tbl [0:TABLE_SIZE-1];

    logic [31:0] key_q;
    logic [15:0] position_q;
    logic write_q;
    logic [TABLE_LB-1:0] probe_addr;
    logic [TABLE_LB-1:0] probe_count;
    logic [31:0] slot_key;
    logic [15:0] slot_position;
    logic slot_valid;

    hash_function hash_unit (
        .data_in(data_in),
        .hash_out(hash_addr)
    );

    assign request_ready = (state == IDLE) && !rst;


    always_ff @(posedge clk) begin
        if (state == READ_SLOT) begin
            slot_key <= keys[probe_addr];
            slot_position <= tbl[probe_addr];
            slot_valid <= valid_bits[probe_addr];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            valid_bits <= '0;
            response_valid <= 1'b0;
            previous_pos <= '0;
            valid <= 1'b0;
            table_full <= 1'b0;
            key_q <= '0;
            position_q <= '0;
            write_q <= 1'b0;
            probe_addr <= '0;
            probe_count <= '0;
        end else begin
            response_valid <= 1'b0;
            case (state)
                IDLE: begin
                    if (request_valid && request_ready) begin
                        key_q <= data_in;
                        position_q <= current_pos;
                        write_q <= write_en;
                        probe_addr <= hash_addr[TABLE_LB-1:0];
                        probe_count <= '0;
                        state <= READ_SLOT;
                    end
                end
                READ_SLOT: state <= CHECK_SLOT;
                CHECK_SLOT: begin
                    if (!slot_valid) begin
                        previous_pos <= '0;
                        valid <= 1'b0;
                        table_full <= 1'b0;
                        response_valid <= 1'b1;
                        if (write_q) begin
                            keys[probe_addr] <= key_q;
                            tbl[probe_addr] <= position_q;
                            valid_bits[probe_addr] <= 1'b1;
                        end
                        state <= IDLE;
                    end else if (slot_key == key_q) begin
                        previous_pos <= slot_position;
                        valid <= 1'b1;
                        table_full <= 1'b0;
                        response_valid <= 1'b1;
                        if (write_q)
                            tbl[probe_addr] <= position_q;
                        state <= IDLE;
                    end else if (&probe_count) begin

                        previous_pos <= '0;
                        valid <= 1'b0;
                        table_full <= 1'b1;
                        response_valid <= 1'b1;
                        state <= IDLE;
                    end else begin
                        probe_addr <= probe_addr + 1'b1;
                        probe_count <= probe_count + 1'b1;
                        state <= READ_SLOT;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
