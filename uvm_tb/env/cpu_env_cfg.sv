class cpu_env_cfg extends uvm_object;
    string program_hex;
    string ref_trace;
    string ref_summary;
    string ref_events;
    string coverage_report;
    int unsigned max_cycles = 2000;

    `uvm_object_utils_begin(cpu_env_cfg)
        `uvm_field_string(program_hex, UVM_DEFAULT)
        `uvm_field_string(ref_trace, UVM_DEFAULT)
        `uvm_field_string(ref_summary, UVM_DEFAULT)
        `uvm_field_string(ref_events, UVM_DEFAULT)
        `uvm_field_string(coverage_report, UVM_DEFAULT)
        `uvm_field_int(max_cycles, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "cpu_env_cfg");
        super.new(name);
    endfunction
endclass
