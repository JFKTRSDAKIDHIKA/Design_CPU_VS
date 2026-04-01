package cpu_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "uvm_tb/agents/cpu_mem_item.sv"
    `include "uvm_tb/agents/cpu_retire_item.sv"
    `include "uvm_tb/env/cpu_env_cfg.sv"
    `include "uvm_tb/agents/cpu_mem_driver.sv"
    `include "uvm_tb/agents/cpu_mem_monitor.sv"
    `include "uvm_tb/agents/cpu_memory_agent.sv"
    `include "uvm_tb/coverage/cpu_coverage_collector.sv"
    `include "uvm_tb/scoreboard/cpu_scoreboard.sv"
    `include "uvm_tb/seq/cpu_virtual_sequencer.sv"
    `include "uvm_tb/seq/cpu_base_vseq.sv"
    `include "uvm_tb/env/cpu_env.sv"
    `include "uvm_tb/tests/cpu_base_test.sv"
    `include "uvm_tb/tests/cpu_smoke_test.sv"
    `include "uvm_tb/tests/cpu_directed_test.sv"
    `include "uvm_tb/tests/cpu_random_test.sv"
endpackage
