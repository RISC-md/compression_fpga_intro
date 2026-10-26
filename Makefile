TOP := lz4_top
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

.PHONY: all test lint waves clean

all: $(BIN)

$(BIN): $(RTL_SRCS) $(TEST_SRCS) $(RTL_LIST) $(TEST_LIST)
	mkdir -p $(BUILD) && $(VERILATOR) $(VFLAGS) -CFLAGS "$(CFLAGS)" -LDFLAGS "$(LDFLAGS)" -f $(RTL_LIST) $(TEST_SRCS)

test: $(BIN)
	cd $(BUILD) && ./V$(TOP) $(abspath $(TESTFILE)) +verilator+rand+reset+2 +verilator+seed+$$RANDOM

lint:
	$(VERILATOR) --lint-only -Wall --top-module $(TOP) -Irtl -f $(RTL_LIST)

waves: test
	gtkwave $(BUILD)/dump.vcd &

clean:
	rm -rf $(BUILD)