ROOT_DIR := $(abspath .)
BUILD_DIR := $(ROOT_DIR)/build/vcs_debug
VCS_CSRC_DIR := $(BUILD_DIR)/csrc
SIMV := $(BUILD_DIR)/simv
COMPILE_LOG := $(BUILD_DIR)/compile.log
RUN_LOG := $(BUILD_DIR)/run.log
WAVE_DIR := $(ROOT_DIR)/build/waves
FILELIST := $(ROOT_DIR)/vsrc/files.f
CPP_SRC := $(ROOT_DIR)/csrc/debugger.cpp
TB_SRC := $(ROOT_DIR)/tb/tb_top.sv
MEM_SRC := $(ROOT_DIR)/tb/memory_model.sv
VCS ?= vcs
VCS_FLAGS := -full64 -sverilog -timescale=1ns/1ps -debug_access+all -Mdir=$(VCS_CSRC_DIR) -cpp g++ -cc gcc
CPP_FLAGS := -std=c++17

.PHONY: debug-build debug-run clean

debug-build:
	mkdir -p $(BUILD_DIR) $(WAVE_DIR)
	$(VCS) $(VCS_FLAGS) \
		-CFLAGS "$(CPP_FLAGS)" \
		-o $(SIMV) \
		-top tb_top \
		-l $(COMPILE_LOG) \
		-f $(FILELIST) \
		$(MEM_SRC) \
		$(TB_SRC) \
		$(CPP_SRC)

debug-run: debug-build
	mkdir -p $(WAVE_DIR)
	$(SIMV) -no_save -l $(RUN_LOG)

clean:
	rm -rf $(BUILD_DIR) $(WAVE_DIR)
