class cpu_env extends uvm_env;
    cpu_memory_agent        mem_agent;
    cpu_scoreboard          scoreboard;
    cpu_coverage_collector  coverage;
    cpu_virtual_sequencer   vseqr;

    `uvm_component_utils(cpu_env)

    function new(string name = "cpu_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mem_agent   = cpu_memory_agent::type_id::create("mem_agent", this);
        scoreboard  = cpu_scoreboard::type_id::create("scoreboard", this);
        coverage    = cpu_coverage_collector::type_id::create("coverage", this);
        vseqr       = cpu_virtual_sequencer::type_id::create("vseqr", this);
        mem_agent.is_active = UVM_ACTIVE;
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        mem_agent.monitor.retire_ap.connect(scoreboard.retire_imp);
        mem_agent.monitor.retire_ap.connect(coverage.retire_imp);
        mem_agent.monitor.mem_ap.connect(coverage.mem_imp);
    endfunction
endclass
