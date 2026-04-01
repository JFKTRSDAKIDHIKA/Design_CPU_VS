class cpu_directed_test extends cpu_base_test;
    `uvm_component_utils(cpu_directed_test)

    function new(string name = "cpu_directed_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
