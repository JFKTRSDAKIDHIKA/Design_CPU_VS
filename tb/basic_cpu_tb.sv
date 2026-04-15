module basic_cpu_tb;
    localparam logic [2:0] STAGE_EXECUTE_SINGLE = 3'b011;
    localparam logic [2:0] STAGE_EXECUTE_DOUBLE = 3'b111;
    localparam int unsigned DEFAULT_STEPS = 1;
    localparam int unsigned DEFAULT_MEM_WORDS = 16;
    localparam int unsigned DEFAULT_MAX_CYCLES = 10000;

    logic        reset;
    logic        clk;
    logic        wr;
    logic        c;
    logic        z;
    logic        v;
    logic        s;
    logic [1:0]  sel;
    logic [3:0]  reg_sel;
    tri   [15:0] data_bus;
    logic [15:0] address_bus;
    logic [15:0] reg_data;
    logic [2:0]  prev_stage;

    string step_mode;
    string mem_file;
    string vpd_file;
    int unsigned step_target;
    int unsigned reset_cycles;
    int unsigned mem_words;
    int unsigned max_cycles;
    bit dump_regs_each_step;
    bit dump_mem_each_step;
    bit dump_final_state;
    bit finished;
    bit step_enable;
    int unsigned cycle_count;
    int unsigned instruction_count;
    logic [15:0] mem_start;

    cpu_top dut (
        .reset(reset),
        .clk(clk),
        .wr(wr),
        .c(c),
        .z(z),
        .v(v),
        .s(s),
        .sel(sel),
        .reg_sel(reg_sel),
        .data_bus(data_bus),
        .address_bus(address_bus),
        .reg_data(reg_data)
    );

    memory_model u_mem (
        .clk(clk),
        .wr(wr),
        .address_bus(address_bus),
        .data_bus(data_bus)
    );

    always #5 clk = ~clk;

    task automatic dump_registers(input string reason);
        begin
            $display("==== Register Dump (%s) ====", reason);
            for (int i = 0; i < 16; i++) begin
                $display("R%0d = 0x%04h", i, dut.u_core.u_reg_file.regs[i]);
            end
            $display(
                "PC=0x%04h IR=0x%04h ADDR=0x%04h DATA=0x%04h STAGE=%0b FLAGS[CZVS]=%0d%0d%0d%0d",
                dut.u_core.pc_bus,
                dut.u_core.instruction,
                address_bus,
                data_bus,
                dut.u_core.execution_stage,
                c,
                z,
                v,
                s
            );
        end
    endtask

    task automatic dump_memory(input logic [15:0] start_addr, input int unsigned words, input string reason);
        begin
            $display("==== Memory Dump (%s) @0x%04h count=%0d ====", reason, start_addr, words);
            for (int unsigned i = 0; i < words; i++) begin
                $display("MEM[0x%04h] = 0x%04h", start_addr + i[15:0], u_mem.mem[start_addr + i[15:0]]);
            end
        end
    endtask

    task automatic dump_state(input string reason);
        begin
            $display(
                "[tb] %s cycles=%0d instructions=%0d wr=%0d stage=%0b",
                reason,
                cycle_count,
                instruction_count,
                wr,
                dut.u_core.execution_stage
            );
            if (dump_regs_each_step || reason == "final") begin
                dump_registers(reason);
            end
            if (dump_mem_each_step || reason == "final") begin
                dump_memory(mem_start, mem_words, reason);
            end
        end
    endtask

    function automatic bit instruction_retired();
        instruction_retired =
            (prev_stage == STAGE_EXECUTE_SINGLE) ||
            (prev_stage == STAGE_EXECUTE_DOUBLE);
    endfunction

    task automatic finish_simulation(input string reason);
        begin
            if (!finished) begin
                finished = 1'b1;
                if (dump_final_state) begin
                    dump_state("final");
                end
                $display("[tb] stop reason: %s", reason);
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b0;
        sel = 2'b00;
        reg_sel = 4'h0;
        prev_stage = 3'b100;
        finished = 1'b0;
        step_enable = 1'b0;
        cycle_count = 0;
        instruction_count = 0;

        step_mode = "cycle";
        mem_file = "sw/mult8.hex";
        step_target = DEFAULT_STEPS;
        reset_cycles = 2;
        mem_start = 16'h0000;
        mem_words = DEFAULT_MEM_WORDS;
        max_cycles = DEFAULT_MAX_CYCLES;
        dump_regs_each_step = 1'b1;
        dump_mem_each_step = 1'b0;
        dump_final_state = 1'b1;

        void'($value$plusargs("mem=%s", mem_file));
        void'($value$plusargs("step_mode=%s", step_mode));
        void'($value$plusargs("steps=%d", step_target));
        void'($value$plusargs("reset_cycles=%d", reset_cycles));
        void'($value$plusargs("mem_start=%h", mem_start));
        void'($value$plusargs("mem_words=%d", mem_words));
        void'($value$plusargs("max_cycles=%d", max_cycles));
        void'($value$plusargs("dump_regs=%d", dump_regs_each_step));
        void'($value$plusargs("dump_mem=%d", dump_mem_each_step));
        void'($value$plusargs("dump_final=%d", dump_final_state));

        if ($value$plusargs("vpd=%s", vpd_file)) begin
            $vcdplusfile(vpd_file);
            $vcdpluson(0, basic_cpu_tb);
        end

        if (step_mode != "cycle" && step_mode != "inst") begin
            $fatal(1, "[tb] unsupported +step_mode=%s, expected cycle or inst", step_mode);
        end

        $display(
            "[tb] config mem=%s step_mode=%s steps=%0d reset_cycles=%0d mem_start=0x%04h mem_words=%0d",
            mem_file,
            step_mode,
            step_target,
            reset_cycles,
            mem_start,
            mem_words
        );

        u_mem.load_hex(mem_file);

        repeat (reset_cycles) @(posedge clk);
        reset = 1'b1;
        $display("[tb] reset released");
        @(negedge clk);
        step_enable = 1'b1;
    end

    always @(negedge clk or negedge reset) begin
        if (!reset) begin
            prev_stage <= 3'b100;
        end else begin
            prev_stage <= dut.u_core.execution_stage;
        end
    end

    always @(posedge clk) begin
        int unsigned next_cycle_count;
        int unsigned next_instruction_count;
        if (!reset || finished || !step_enable) begin
            if (!reset) begin
                cycle_count = 0;
                instruction_count = 0;
            end
        end else begin
            next_cycle_count = cycle_count + 1;
            next_instruction_count = instruction_count;
            cycle_count = next_cycle_count;

            if (instruction_retired()) begin
                next_instruction_count = instruction_count + 1;
                instruction_count = next_instruction_count;
            end

            #1;
            if (step_mode == "cycle") begin
                dump_state($sformatf("cycle_step_%0d", next_cycle_count));
                if (next_cycle_count >= step_target) begin
                    finish_simulation($sformatf("reached %0d cycle steps", step_target));
                end
            end else if (instruction_retired()) begin
                dump_state($sformatf("inst_step_%0d", next_instruction_count));
                if (next_instruction_count >= step_target) begin
                    finish_simulation($sformatf("reached %0d instruction steps", step_target));
                end
            end

            if (next_cycle_count >= max_cycles) begin
                $fatal(1, "[tb] timeout after %0d cycles", next_cycle_count);
            end
        end
    end
endmodule
