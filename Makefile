TOP := lz4_top
BUILD := build
RTL_LIST := rtl.f
RTL_SRCS := $(shell cat $(RTL_LIST))
TEST_LIST := tests.f
TEST_SRCS := $(shell cat $(TEST_LIST))
BIN = $(BUILD)/V$(TOP)
TESTFILE ?= $(dir $(firstword $(TEST_SRCS)))example.txt

VERILATOR ?= verilator
VFLAGS := --cc --exe --build -j 0 -Wall --trace --assert --x-assign unique --x-initial unique --top-module $(TOP) -Irtl -Mdir $(BUILD) --timescale 1ns/1ps
CFLAGS := -std=c++17 -O2
LDFLAGS := -llz4

.PHONY: all test test-hash lint lint-match waves clean tb

all: $(BIN)

$(BIN): $(RTL_SRCS) $(TEST_SRCS) $(RTL_LIST) $(TEST_LIST)
	mkdir -p $(BUILD) && $(VERILATOR) $(VFLAGS) -CFLAGS "$(CFLAGS)" -LDFLAGS "$(LDFLAGS)" -f $(RTL_LIST) $(TEST_SRCS)

test: $(BIN)
	cd $(BUILD) && ./V$(TOP) $(abspath $(TESTFILE)) +verilator+rand+reset+2 +verilator+seed+$$RANDOM

lint:
	$(VERILATOR) --lint-only -Wall --top-module $(TOP) -Irtl -f $(RTL_LIST)

lint-match:
	$(VERILATOR) --lint-only -Wall --top-module match_finder -Irtl -f $(RTL_LIST)

test-hash:
	mkdir -p $(BUILD)/hash_small $(BUILD)/hash_default
	$(VERILATOR) --binary -j 2 -Wall --timescale 1ns/1ps --assert --top-module tb_hash_table -Mdir $(BUILD)/hash_small -f $(RTL_LIST) tb/tb_hash_table.sv
	./$(BUILD)/hash_small/Vtb_hash_table
	$(VERILATOR) --binary -j 2 -Wall --timescale 1ns/1ps --assert --top-module tb_hash_table -GTABLE_LB=12 -Mdir $(BUILD)/hash_default -f $(RTL_LIST) tb/tb_hash_table.sv
	./$(BUILD)/hash_default/Vtb_hash_table

waves: test
	gtkwave $(BUILD)/dump.vcd &

clean:
	rm -rf $(BUILD)

tb:
	mkdir -p $(BUILD)/$(TB)
	$(VERILATOR) --binary -j 0 -Wall --timescale 1ns/1ps --trace --assert -Mdir $(BUILD)/$(TB) --top-module $(TB) -f $(RTL_LIST) tb/$(TB).sv 
	./$(BUILD)/$(TB)/V$(TB)
