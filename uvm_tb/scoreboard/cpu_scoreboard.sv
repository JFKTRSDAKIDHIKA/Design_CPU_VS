class cpu_scoreboard extends uvm_component;
    uvm_analysis_imp #(cpu_retire_item, cpu_scoreboard) retire_imp;
    cpu_env_cfg cfg;
    uvm_event done_ev;

    cpu_retire_item expected_q[$];
    bit [15:0] expected_regs[16];
    bit [15:0] expected_pc;
    bit        expected_c;
    bit        expected_z;
    bit        expected_v;
    bit        expected_s;
    int unsigned expected_steps;
    int unsigned observed_steps;
    int unsigned mismatch_count;

    `uvm_component_utils(cpu_scoreboard)

    function new(string name = "cpu_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        retire_imp = new("retire_imp", this);
        done_ev    = new("done_ev");
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_env_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_type_name(), "missing env cfg")
        end
        load_reference_trace();
        load_reference_summary();
    endfunction

    function void load_reference_trace();
        int fd;
        string line;
        int step;
        int unsigned addr;
        int unsigned pc;
        int unsigned ir;
        int unsigned regs[16];
        int c;
        int z;
        int v;
        int s;
        cpu_retire_item item;

        fd = $fopen(cfg.ref_trace, "r");
        if (fd == 0) begin
            `uvm_fatal(get_type_name(), $sformatf("failed to open ref trace %s", cfg.ref_trace))
        end

        while ($fgets(line, fd)) begin
            if ($sscanf(
                line,
                "TRACE step=%d addr=%h pc=%h ir=%h R0=%h R1=%h R2=%h R3=%h R4=%h R5=%h R6=%h R7=%h R8=%h R9=%h R10=%h R11=%h R12=%h R13=%h R14=%h R15=%h C=%d Z=%d V=%d S=%d",
                step, addr, pc, ir,
                regs[0], regs[1], regs[2], regs[3], regs[4], regs[5], regs[6], regs[7],
                regs[8], regs[9], regs[10], regs[11], regs[12], regs[13], regs[14], regs[15],
                c, z, v, s
            ) == 24) begin
                item = cpu_retire_item::type_id::create($sformatf("exp_%0d", expected_q.size()));
                item.step       = step;
                item.instr_addr = addr[15:0];
                item.pc         = pc[15:0];
                item.ir         = ir[15:0];
                item.c          = c;
                item.z          = z;
                item.v          = v;
                item.s          = s;
                for (int idx = 0; idx < 16; idx++) begin
                    item.regs[idx] = regs[idx][15:0];
                end
                expected_q.push_back(item);
            end
        end
        $fclose(fd);
        expected_steps = expected_q.size();
    endfunction

    function void load_reference_summary();
        int fd;
        string line;
        int reg_idx;
        int unsigned reg_val;
        int unsigned pc_val;
        int tmp;

        fd = $fopen(cfg.ref_summary, "r");
        if (fd == 0) begin
            `uvm_fatal(get_type_name(), $sformatf("failed to open ref summary %s", cfg.ref_summary))
        end
        while ($fgets(line, fd)) begin
            if ($sscanf(line, "steps=%d", tmp) == 1) begin
                expected_steps = tmp;
            end else if ($sscanf(line, "pc=0x%h", pc_val) == 1) begin
                expected_pc = pc_val[15:0];
            end else if ($sscanf(line, "r%d=0x%h", reg_idx, reg_val) == 2) begin
                if ((reg_idx >= 0) && (reg_idx < 16)) begin
                    expected_regs[reg_idx] = reg_val[15:0];
                end
            end else if ($sscanf(line, "c=%d", tmp) == 1) begin
                expected_c = tmp;
            end else if ($sscanf(line, "z=%d", tmp) == 1) begin
                expected_z = tmp;
            end else if ($sscanf(line, "v=%d", tmp) == 1) begin
                expected_v = tmp;
            end else if ($sscanf(line, "s=%d", tmp) == 1) begin
                expected_s = tmp;
            end
        end
        $fclose(fd);
    endfunction

    function void compare_item(cpu_retire_item got, cpu_retire_item exp);
        if ((got.pc !== exp.pc) || (got.ir !== exp.ir) ||
            (got.c !== exp.c) || (got.z !== exp.z) || (got.v !== exp.v) || (got.s !== exp.s)) begin
            mismatch_count++;
            `uvm_error(get_type_name(), $sformatf("retire mismatch\nexp: %s\ngot: %s", exp.convert2string(), got.convert2string()))
            return;
        end
        for (int idx = 0; idx < 16; idx++) begin
            if (got.regs[idx] !== exp.regs[idx]) begin
                mismatch_count++;
                `uvm_error(get_type_name(), $sformatf("register mismatch at step %0d R%0d exp=%04h got=%04h", got.step, idx, exp.regs[idx], got.regs[idx]))
                return;
            end
        end
    endfunction

    function void write(cpu_retire_item item);
        if (observed_steps >= expected_q.size()) begin
            mismatch_count++;
            `uvm_error(get_type_name(), $sformatf("unexpected extra retire: %s", item.convert2string()))
            return;
        end

        compare_item(item, expected_q[observed_steps]);
        observed_steps++;

        if (observed_steps == expected_q.size()) begin
            for (int idx = 0; idx < 16; idx++) begin
                if (item.regs[idx] !== expected_regs[idx]) begin
                    mismatch_count++;
                    `uvm_error(get_type_name(), $sformatf("final summary mismatch R%0d exp=%04h got=%04h", idx, expected_regs[idx], item.regs[idx]))
                end
            end
            if ((item.pc !== expected_pc) || (item.c !== expected_c) || (item.z !== expected_z) || (item.v !== expected_v) || (item.s !== expected_s)) begin
                mismatch_count++;
                `uvm_error(get_type_name(), "final flag/pc mismatch against reference summary")
            end
            done_ev.trigger();
        end
    endfunction

    function bit passed();
        return (mismatch_count == 0) && (observed_steps == expected_steps);
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (!passed()) begin
            `uvm_error(get_type_name(), $sformatf("scoreboard failed observed=%0d expected=%0d mismatches=%0d", observed_steps, expected_steps, mismatch_count))
        end else begin
            `uvm_info(get_type_name(), $sformatf("scoreboard passed with %0d retire compares", observed_steps), UVM_LOW)
        end
    endfunction
endclass
