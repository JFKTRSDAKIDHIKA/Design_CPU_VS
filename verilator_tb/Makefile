# Verilator C++ testbench for the new C-class instruction CALLA addr16.
# `make build`  -> compiles a self-contained simv binary
# `make run`    -> runs it
# `make clean`  -> removes build artifacts

ROOT_DIR  := $(abspath ..)
TB_DIR    := $(abspath .)
OBJ_DIR   := $(TB_DIR)/obj_dir
SIMV      := $(OBJ_DIR)/Vverilator_top
TRACE_VCD := $(TB_DIR)/calla.vcd

VSRC := \
    $(ROOT_DIR)/vsrc/alu.sv \
    $(ROOT_DIR)/vsrc/controller.sv \
    $(ROOT_DIR)/vsrc/cpu_core.sv \
    $(ROOT_DIR)/vsrc/cpu_top.sv \
    $(ROOT_DIR)/vsrc/flag_reg.sv \
    $(ROOT_DIR)/vsrc/instruction_reg.sv \
    $(ROOT_DIR)/vsrc/pc.sv \
    $(ROOT_DIR)/vsrc/reg_file.sv \
    $(ROOT_DIR)/vsrc/reg_out.sv \
    $(ROOT_DIR)/vsrc/reg_testa.sv \
    $(ROOT_DIR)/vsrc/t1.sv \
    $(ROOT_DIR)/vsrc/t2.sv \
    $(ROOT_DIR)/vsrc/execution_stage_fsm.sv \
    $(TB_DIR)/verilator_top.sv

VFLAGS := \
    --cc \
    --exe \
    --build \
    --trace \
    -O2 \
    -Wno-fatal \
    -Wno-MULTIDRIVEN \
    -Wno-UNOPTFLAT \
    -Wno-WIDTH \
    -Wno-CASEINCOMPLETE \
    -Wno-UNUSED \
    -Wno-DECLFILENAME \
    -Wno-PINMISSING \
    --top-module verilator_top

.PHONY: all build run clean

all: build

build: $(SIMV)

$(SIMV): $(VSRC) sim_main.cpp Makefile
	verilator $(VFLAGS) $(VSRC) sim_main.cpp --Mdir $(OBJ_DIR)

run: build
	@echo "Running CALLA verilator testbench..."
	@$(SIMV) +verilator+rand+reset+2 || true
	@echo "Trace (if any) was written to $(TRACE_VCD)"

clean:
	rm -rf $(OBJ_DIR) $(TRACE_VCD)
