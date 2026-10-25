#include "Vlz4_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    Vlz4_top dut;
    VerilatedVcdC tfp;
    return 1; // skeleton
}