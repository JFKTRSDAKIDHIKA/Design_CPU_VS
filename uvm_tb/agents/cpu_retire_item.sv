class cpu_retire_item extends uvm_sequence_item;
    rand int unsigned step;
    rand int unsigned cycle;
    rand bit [15:0]  instr_addr;
    rand bit [15:0]  pc;
    rand bit [15:0]  ir;
    rand bit [7:0]   opcode;
    rand bit [3:0]   dr;
    rand bit [3:0]   sr;
    rand bit [15:0]  extra_word;
    rand bit [1:0]   instr_words;
    rand bit         is_branch;
    rand bit         branch_taken;
    rand bit [15:0]  branch_target;
    rand bit [15:0]  regs[16];
    rand bit         c;
    rand bit         z;
    rand bit         v;
    rand bit         s;
    rand bit         pre_c;
    rand bit         pre_z;
    rand bit         pre_v;
    rand bit         pre_s;

    `uvm_object_utils(cpu_retire_item)

    function new(string name = "cpu_retire_item");
        super.new(name);
    endfunction

    function string convert2string();
        string reg_dump = "";
        for (int idx = 0; idx < 16; idx++) begin
            reg_dump = {reg_dump, $sformatf(" R%0d=%04h", idx, regs[idx])};
        end
        return $sformatf(
            "step=%0d cycle=%0d addr=%04h pc=%04h ir=%04h op=%02h dr=%0d sr=%0d words=%0d ext=%04h branch=%0d taken=%0d target=%04h%s pre[CZVS]=%0d%0d%0d%0d post[CZVS]=%0d%0d%0d%0d",
            step, cycle, instr_addr, pc, ir, opcode, dr, sr, instr_words, extra_word, is_branch, branch_taken, branch_target, reg_dump, pre_c, pre_z, pre_v, pre_s, c, z, v, s
        );
    endfunction
endclass
