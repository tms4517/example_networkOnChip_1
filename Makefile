# Copyright (c) 2026 Tej Sanghavi.
#
# PicoRV32 + APB timer/GPIO SoC on a networkOnChip mesh.
#
#   make firmware  cross-compile firmware/ into build/firmware/firmware.hex
#   make noc       generate the NoC (generated/) from config/socNoc.json
#   make lint      Verilator -Wall on the SoC + svlint on rtl/
#   make sim       build and run the boot testbench (PASS/FAIL)
#   make waves     as sim, plus build/waves.fst opened in gtkwave
#   make clean     remove build/ and generated/
#
# Tools: RISC-V GCC (RISCV_PREFIX), Verilator 5, svlint, python3.
# The --timing testbench needs a C++20 compiler (GCC >= 10): pass CXX=...

RISCV_PREFIX ?= riscv64-unknown-elf-
PYTHON ?= python3
CXX ?= g++
SIM_ARGS ?=

BUILD_DIR = build
FW_DIR = $(BUILD_DIR)/firmware
NOC_DIR = generated
NOC_TOP = $(NOC_DIR)/rtl/nocSoc.sv
NOC_CONFIG = config/socNoc.json
NOC_GEN = networkOnChip/autoConfiguration/nocGen.py

RAM_WORDS = 4096
FW_CFLAGS = -march=rv32i -mabi=ilp32 -O2 -ffreestanding -fno-builtin \
  -nostdlib -Wall -Wextra -Werror
FW_SOURCES = firmware/start.S firmware/main.c
FW_DEPS = $(FW_SOURCES) firmware/soc.h firmware/link.ld firmware/makehex.py
FW_HEX = $(FW_DIR)/firmware.hex

RTL_SOURCES = rtl/socTop.sv rtl/axiLiteSram.sv
VERILATOR_FLAGS = --binary --timing -Wall --timescale 1ns/1ps \
  -f rtl/soc.f tb/tb_soc.sv --top-module tb_soc \
  -MAKEFLAGS "CXX=$(CXX) LINK=$(CXX) CFG_CXXFLAGS_PCH_I=-include" \
  -CFLAGS -std=c++20 -LDFLAGS "-pthread -static-libstdc++"

.PHONY: all
all: lint sim

# {{{ Firmware

.PHONY: firmware
firmware: $(FW_HEX)

$(FW_HEX): $(FW_DEPS)
	mkdir -p $(FW_DIR)
	$(RISCV_PREFIX)gcc $(FW_CFLAGS) -T firmware/link.ld \
	  -o $(FW_DIR)/firmware.elf $(FW_SOURCES)
	$(RISCV_PREFIX)objdump -d $(FW_DIR)/firmware.elf > $(FW_DIR)/firmware.lst
	$(RISCV_PREFIX)objcopy -O binary $(FW_DIR)/firmware.elf \
	  $(FW_DIR)/firmware.bin
	$(PYTHON) firmware/makehex.py $(FW_DIR)/firmware.bin $(RAM_WORDS) > $@
	$(RISCV_PREFIX)size $(FW_DIR)/firmware.elf

# }}} Firmware

# {{{ NoC

.PHONY: noc
noc: $(NOC_TOP)

$(NOC_TOP): $(NOC_CONFIG) $(NOC_GEN)
	$(PYTHON) $(NOC_GEN) $(NOC_CONFIG) -o $(NOC_DIR)

# }}} NoC

# {{{ Lint

.PHONY: lint
lint: $(NOC_TOP)
	verilator --lint-only -Wall -f rtl/soc.f --top-module socTop
	svlint -c .svlint.toml $(RTL_SOURCES)

# }}} Lint

# {{{ Simulation

SIM_BINARY = $(BUILD_DIR)/sim/Vtb_soc
WAVES_BINARY = $(BUILD_DIR)/waves/Vtb_soc

.PHONY: sim
sim: $(SIM_BINARY) $(FW_HEX)
	./$(SIM_BINARY) +firmware=$(FW_HEX) $(SIM_ARGS)

$(SIM_BINARY): $(NOC_TOP) $(RTL_SOURCES) rtl/soc.f tb/tb_soc.sv
	verilator $(VERILATOR_FLAGS) -Mdir $(BUILD_DIR)/sim

.PHONY: waves
waves: $(WAVES_BINARY) $(FW_HEX)
	./$(WAVES_BINARY) +firmware=$(FW_HEX) $(SIM_ARGS)
	gtkwave $(BUILD_DIR)/waves.fst &

$(WAVES_BINARY): $(NOC_TOP) $(RTL_SOURCES) rtl/soc.f tb/tb_soc.sv
	verilator $(VERILATOR_FLAGS) --trace-fst -DTRACE -Mdir $(BUILD_DIR)/waves

# }}} Simulation

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) $(NOC_DIR)
