class cpu_mem_item extends uvm_sequence_item;
    typedef enum int {MEM_READ, MEM_WRITE} mem_kind_e;

    rand mem_kind_e  kind;
    rand bit [15:0]  addr;
    rand bit [15:0]  data;
    rand int unsigned cycle;

    `uvm_object_utils_begin(cpu_mem_item)
        `uvm_field_enum(mem_kind_e, kind, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_HEX)
        `uvm_field_int(data, UVM_HEX)
        `uvm_field_int(cycle, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "cpu_mem_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("kind=%s addr=0x%04h data=0x%04h cycle=%0d",
            (kind == MEM_READ) ? "READ" : "WRITE", addr, data, cycle);
    endfunction
endclass
