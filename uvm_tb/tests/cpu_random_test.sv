class cpu_random_test extends cpu_base_test;
    `uvm_component_utils(cpu_random_test)

    function new(string name = "cpu_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
