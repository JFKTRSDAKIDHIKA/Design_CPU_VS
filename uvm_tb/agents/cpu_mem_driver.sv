class cpu_mem_driver extends uvm_driver #(cpu_mem_item);
    virtual cpu_core_if vif;
    cpu_env_cfg         cfg;

    `uvm_component_utils(cpu_mem_driver)

    function new(string name = "cpu_mem_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cpu_core_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "missing virtual interface")
        end
        if (!uvm_config_db#(cpu_env_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_type_name(), "missing env cfg")
        end
    endfunction

    task run_phase(uvm_phase phase);
        vif.init_signals();
        vif.load_hex(cfg.program_hex);
        repeat (2) @(posedge vif.clk);
        vif.reset <= 1'b1;
        forever begin
            @(posedge vif.clk);
            #1step;
            vif.commit_write_if_needed();
        end
    endtask
endclass
