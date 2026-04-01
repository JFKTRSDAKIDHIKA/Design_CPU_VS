class cpu_mem_monitor extends uvm_component;
    localparam bit [2:0] STAGE_EXECUTE_SINGLE = 3'b011;
    localparam bit [2:0] STAGE_EXECUTE_DOUBLE = 3'b111;
    localparam bit [2:0] STAGE_FETCH_DECODE   = 3'b001;

    virtual cpu_core_if vif;
    uvm_analysis_port #(cpu_mem_item)    mem_ap;
    uvm_analysis_port #(cpu_retire_item) retire_ap;

    int unsigned cycle_count;
    int unsigned retire_count;
    bit [2:0] prev_stage;
    bit [15:0] current_seq_pc;
    bit prev_c;
    bit prev_z;
    bit prev_v;
    bit prev_s;

    `uvm_component_utils(cpu_mem_monitor)

    function new(string name = "cpu_mem_monitor", uvm_component parent = null);
        super.new(name, parent);
        mem_ap    = new("mem_ap", this);
        retire_ap = new("retire_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cpu_core_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "missing virtual interface")
        end
    endfunction

    function automatic bit is_double_word_opcode(bit [7:0] opcode);
        return opcode inside {8'h80, 8'h81};
    endfunction

    function automatic bit is_branch_opcode(bit [7:0] opcode);
        return opcode inside {8'h40, 8'h41, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47, 8'h80};
    endfunction

    function automatic bit [15:0] sign_extend8(bit [7:0] value);
        return {{8{value[7]}}, value};
    endfunction

    task sample_retire();
        cpu_retire_item item;
        logic [15:0] regs[16];
        logic [15:0] pc;
        logic [15:0] ir;
        logic out_c;
        logic out_z;
        logic out_v;
        logic out_s;

        vif.sample_state(regs, pc, ir, out_c, out_z, out_v, out_s);

        item = cpu_retire_item::type_id::create("item");
        item.step        = retire_count;
        item.cycle       = cycle_count;
        item.pc          = pc;
        item.ir          = ir;
        item.opcode      = ir[15:8];
        item.dr          = ir[7:4];
        item.sr          = ir[3:0];
        item.instr_words = is_double_word_opcode(ir[15:8]) ? 2 : 1;
        item.instr_addr  = current_seq_pc - item.instr_words;
        item.extra_word  = item.instr_words == 2 ? vif.mem[(current_seq_pc - 16'h0001) & 16'hFFFF] : 16'h0000;
        item.is_branch   = is_branch_opcode(ir[15:8]);
        item.pre_c       = prev_c;
        item.pre_z       = prev_z;
        item.pre_v       = prev_v;
        item.pre_s       = prev_s;
        item.c           = out_c;
        item.z           = out_z;
        item.v           = out_v;
        item.s           = out_s;
        if (item.opcode == 8'h80) begin
            item.branch_taken  = 1'b1;
            item.branch_target = item.extra_word;
        end else if (item.opcode inside {8'h40, 8'h41, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47}) begin
            bit [15:0] seq_pc = current_seq_pc;
            item.branch_taken  = (pc != seq_pc);
            item.branch_target = item.branch_taken ? pc : seq_pc;
        end else begin
            item.branch_taken  = 1'b0;
            item.branch_target = pc;
        end
        for (int idx = 0; idx < 16; idx++) begin
            item.regs[idx] = regs[idx];
        end
        prev_c = out_c;
        prev_z = out_z;
        prev_v = out_v;
        prev_s = out_s;
        retire_ap.write(item);
        retire_count++;
    endtask

    task emit_mem(bit is_write);
        cpu_mem_item item = cpu_mem_item::type_id::create("item");
        item.kind  = is_write ? cpu_mem_item::MEM_WRITE : cpu_mem_item::MEM_READ;
        item.addr  = vif.address_bus;
        item.data  = is_write ? vif.data_bus : vif.mem[vif.address_bus];
        item.cycle = cycle_count;
        mem_ap.write(item);
    endtask

    task run_phase(uvm_phase phase);
        cycle_count       = 0;
        retire_count      = 0;
        prev_stage        = 3'b100;
        current_seq_pc    = 16'h0000;
        prev_c            = 1'b0;
        prev_z            = 1'b0;
        prev_v            = 1'b0;
        prev_s            = 1'b0;

        forever begin
            @(negedge vif.clk);
            if (!vif.reset) begin
                prev_stage        = 3'b100;
                current_seq_pc    = 16'h0000;
                prev_c            = 1'b0;
                prev_z            = 1'b0;
                prev_v            = 1'b0;
                prev_s            = 1'b0;
            end else begin
                prev_stage = vif.exec_stage;
            end

            @(posedge vif.clk);
            if (!vif.reset) begin
                cycle_count  = 0;
                retire_count = 0;
            end else begin
                cycle_count++;
                #1step;
                if (vif.exec_stage == STAGE_FETCH_DECODE) begin
                    emit_mem(1'b0);
                end
                if ((vif.exec_stage == STAGE_EXECUTE_DOUBLE) && (vif.wr === 1'b1)) begin
                    emit_mem(1'b0);
                end
                if ((vif.exec_stage == STAGE_EXECUTE_DOUBLE) && (vif.wr === 1'b0)) begin
                    emit_mem(1'b1);
                end
                if ((prev_stage == STAGE_EXECUTE_SINGLE) || (prev_stage == STAGE_EXECUTE_DOUBLE)) begin
                    sample_retire();
                end
                if ((vif.exec_stage == STAGE_FETCH_DECODE) || (vif.exec_stage == 3'b101)) begin
                    current_seq_pc = vif.dbg_pc;
                end
            end
        end
    endtask
endclass
