class cpu_smoke_test extends cpu_base_test;
    `uvm_component_utils(cpu_smoke_test)

    function new(string name = "cpu_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
