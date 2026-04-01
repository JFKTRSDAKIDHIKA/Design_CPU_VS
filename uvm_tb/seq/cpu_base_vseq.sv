class cpu_base_vseq extends uvm_sequence #(uvm_sequence_item);
    `uvm_object_utils(cpu_base_vseq)

    function new(string name = "cpu_base_vseq");
        super.new(name);
    endfunction

    task body();
    endtask
endclass
