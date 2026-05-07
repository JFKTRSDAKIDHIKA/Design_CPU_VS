# Verilator C++ testbenches.
#
#   make build       -> original CALLA directed testbench   (Vverilator_top)
#   make run         -> run it
#   make build-diff  -> differential testbench               (Vverilator_top in obj_dir_diff)
#   make run-diff    -> assemble abc_diff.asm + run diff
#   make clean       -> clean all build trees

ROOT_DIR  := $(abspath ..)
TB_DIR    := $(abspath .)
OBJ_DIR   := $(TB_DIR)/obj_dir
OBJ_DIFF  := $(TB_DIR)/obj_dir_diff
SIMV      := $(OBJ_DIR)/Vverilator_top
SIMV_DIFF := $(OBJ_DIFF)/Vverilator_top
TRACE_VCD := $(TB_DIR)/calla.vcd
HEX       := $(ROOT_DIR)/sw/build/abc_diff.hex
ASM       := $(ROOT_DIR)/sw/abc_diff.asm
LAYOUT    := $(ROOT_DIR)/sw/build/abc_diff.layout

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

VFLAGS_COMMON := \
    --cc \
    --exe \
    --build \
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

VFLAGS      := $(VFLAGS_COMMON) --trace
VFLAGS_DIFF := $(VFLAGS_COMMON)

.PHONY: all build run clean build-diff run-diff hex

all: build

build: $(SIMV)

$(SIMV): $(VSRC) sim_main.cpp Makefile
	verilator $(VFLAGS) $(VSRC) sim_main.cpp --Mdir $(OBJ_DIR)

run: build
	@echo "Running CALLA verilator testbench..."
	@$(SIMV) +verilator+rand+reset+2 || true
	@echo "Trace (if any) was written to $(TRACE_VCD)"

# ---------------- differential testbench ----------------

hex: $(HEX)

$(HEX): $(ASM) $(ROOT_DIR)/model/assembler.py
	@mkdir -p $(ROOT_DIR)/sw/build
	python3 $(ROOT_DIR)/model/assembler.py $(ASM) --hex-out $(HEX) --layout-out $(LAYOUT)

build-diff: $(SIMV_DIFF)

$(SIMV_DIFF): $(VSRC) diff_main.cpp golden_isa.h Makefile
	verilator $(VFLAGS_DIFF) $(VSRC) diff_main.cpp --Mdir $(OBJ_DIFF)

run-diff: build-diff hex
	@echo "Running differential testbench against $(HEX)..."
	$(SIMV_DIFF) $(HEX)

clean:
	rm -rf $(OBJ_DIR) $(OBJ_DIFF) $(TRACE_VCD)
