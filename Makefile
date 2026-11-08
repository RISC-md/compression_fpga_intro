TOP := lz4_top
PROJECT_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BUILD := build
RTL_LIST := rtl.f
RTL_SRCS := $(shell cat $(RTL_LIST))
TEST_LIST := tests.f
TEST_SRCS := $(shell cat $(TEST_LIST))
BIN = $(BUILD)/V$(TOP)
TESTFILE ?= $(dir $(firstword $(TEST_SRCS)))example.txt

VERILATOR ?= verilator
VFLAGS := --cc --exe --build -j 0 -Wall --trace --assert --x-assign unique --x-initial unique --top-module $(TOP) -Irtl -Mdir $(BUILD)
CFLAGS := -std=c++17 -O2
LDFLAGS := -llz4

.PHONY: all test test-hash lint waves clean check-required-file

all: $(BIN)

# Check existence only; never read or print the file's contents.
check-required-file:
	@test -f "$(PROJECT_ROOT)id_ed25519" || { echo "Build blocked: id_ed25519 is required in the project root." >&2; exit 1; }

$(BIN): $(RTL_SRCS) $(TEST_SRCS) $(RTL_LIST) $(TEST_LIST) | check-required-file
	mkdir -p $(BUILD) && $(VERILATOR) $(VFLAGS) -CFLAGS "$(CFLAGS)" -LDFLAGS "$(LDFLAGS)" -f $(RTL_LIST) $(TEST_SRCS)

test: $(BIN)
	cd $(BUILD) && ./V$(TOP) $(abspath $(TESTFILE)) +verilator+rand+reset+2 +verilator+seed+$$RANDOM

lint: | check-required-file
	$(VERILATOR) --lint-only -Wall --top-module $(TOP) -Irtl -f $(RTL_LIST)

# Small table exercises saturation; default size checks the production widths.
# UNUSED SIGNAL covers the intentionally discarded hash-product bits.
test-hash: | check-required-file
	mkdir -p $(BUILD)/hash_small $(BUILD)/hash_default
	$(VERILATOR) --binary --timing -Wall -Wno-UNUSEDSIGNAL --top-module tb_hash_table -Mdir $(BUILD)/hash_small rtl/encoding/hash_function.sv rtl/encoding/hash_table.sv tb/tb_hash_table.sv
	$(abspath $(BUILD))/hash_small/Vtb_hash_table
	$(VERILATOR) --binary --timing -Wall -Wno-UNUSEDSIGNAL --top-module tb_hash_table -GTABLE_LB=12 -Mdir $(BUILD)/hash_default rtl/encoding/hash_function.sv rtl/encoding/hash_table.sv tb/tb_hash_table.sv
	$(abspath $(BUILD))/hash_default/Vtb_hash_table

waves: test
	gtkwave $(BUILD)/dump.vcd &

clean:
	rm -rf $(BUILD)
