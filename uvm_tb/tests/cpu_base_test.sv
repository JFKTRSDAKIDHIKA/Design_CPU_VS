class cpu_base_test extends uvm_test;
    virtual cpu_core_if vif;
    cpu_env             env;
    cpu_env_cfg         cfg;
    cpu_base_vseq       vseq;

    `uvm_component_utils(cpu_base_test)

    function new(string name = "cpu_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual cpu_core_if)::get(null, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "missing virtual interface in config_db")
        end

        cfg = cpu_env_cfg::type_id::create("cfg");
        if (!$value$plusargs("program_hex=%s", cfg.program_hex)) begin
            cfg.program_hex = "sw/mult8.hex";
        end
        if (!$value$plusargs("ref_trace=%s", cfg.ref_trace)) begin
            cfg.ref_trace = "logs/ref_trace.txt";
        end
        if (!$value$plusargs("ref_summary=%s", cfg.ref_summary)) begin
            cfg.ref_summary = "logs/ref_summary.txt";
        end
        if (!$value$plusargs("ref_events=%s", cfg.ref_events)) begin
            cfg.ref_events = "logs/ref_events.jsonl";
        end
        if (!$value$plusargs("coverage_report=%s", cfg.coverage_report)) begin
            cfg.coverage_report = "reports/coverage/default.txt";
        end
        void'($value$plusargs("max_cycles=%d", cfg.max_cycles));

        uvm_config_db#(cpu_env_cfg)::set(this, "*", "cfg", cfg);
        uvm_config_db#(virtual cpu_core_if)::set(this, "*", "vif", vif);

        env  = cpu_env::type_id::create("env", this);
        vseq = cpu_base_vseq::type_id::create("vseq");
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        fork
            begin
                env.scoreboard.done_ev.wait_trigger();
            end
            begin
                repeat (cfg.max_cycles) @(posedge vif.clk);
                `uvm_fatal(get_type_name(), $sformatf("timeout after %0d cycles", cfg.max_cycles))
            end
        join_any
        disable fork;
        if (!env.scoreboard.passed()) begin
            `uvm_fatal(get_type_name(), "scoreboard reported failure")
        end
        phase.drop_objection(this);
    endtask
endclass
