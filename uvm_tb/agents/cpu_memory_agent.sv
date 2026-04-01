class cpu_memory_agent extends uvm_agent;
    cpu_mem_driver  driver;
    cpu_mem_monitor monitor;
    uvm_sequencer #(cpu_mem_item) seqr;

    `uvm_component_utils(cpu_memory_agent)

    function new(string name = "cpu_memory_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (is_active == UVM_ACTIVE) begin
            seqr   = uvm_sequencer#(cpu_mem_item)::type_id::create("seqr", this);
            driver = cpu_mem_driver::type_id::create("driver", this);
        end
        monitor = cpu_mem_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(seqr.seq_item_export);
        end
    endfunction
endclass
