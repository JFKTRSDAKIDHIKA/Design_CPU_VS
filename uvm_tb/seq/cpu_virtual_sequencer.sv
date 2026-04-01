class cpu_virtual_sequencer extends uvm_sequencer #(uvm_sequence_item);
    `uvm_component_utils(cpu_virtual_sequencer)

    function new(string name = "cpu_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
