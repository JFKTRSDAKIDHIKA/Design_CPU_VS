module tb_top;
    localparam logic [2:0] STAGE_EXECUTE_SINGLE = 3'b011;
    localparam logic [2:0] STAGE_EXECUTE_DOUBLE = 3'b111;
    localparam int STOP_NONE = 0;
    localparam int STOP_STEP = 1;
    localparam int STOP_BREAKPOINT = 2;
    localparam int STOP_HALTED = 3;
    localparam int STOP_TIMEOUT = 4;
    localparam int STOP_QUIT = 5;
    localparam int DEFAULT_RESET_CYCLES = 2;
    localparam int HALT_REPEAT_THRESHOLD = 3;
    localparam int DEFAULT_MAX_CYCLES = 100000;
    localparam string DEFAULT_MEM_FILE = "sw/mult8.hex";
    localparam string WAVE_FILE = "build/waves/cpu_debug.vpd";

    import "DPI-C" context task debugger_main();

    export "DPI-C" task sv_init;
    export "DPI-C" task sv_reset;
    export "DPI-C" task sv_step_cycles;
    export "DPI-C" task sv_step_instructions;
    export "DPI-C" task sv_run;
    export "DPI-C" task sv_continue;
    export "DPI-C" task sv_quit;
    export "DPI-C" function sv_read_reg;
    export "DPI-C" function sv_read_pc;
    export "DPI-C" function sv_read_mem;
    export "DPI-C" function sv_get_cycle_count;
    export "DPI-C" function sv_get_instr_count;
    export "DPI-C" function sv_is_halted;
    export "DPI-C" function sv_get_last_stop_reason;
    export "DPI-C" task sv_add_breakpoint;
    export "DPI-C" task sv_clear_breakpoints;
    export "DPI-C" task sv_load_hex;
    export "DPI-C" function sv_wave_set;

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

    bit breakpoints [0:16'hFFFF];
    string current_mem_file;
    int unsigned cycle_count;
    int unsigned instruction_count;
    int unsigned halt_repeat_count;
    int unsigned max_cycles;
    int last_stop_reason;
    bit halted;
    bit quit_requested;
    bit wave_enabled;
    bit wave_initialized;

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

    always @(negedge clk or negedge reset) begin
        if (!reset) begin
            prev_stage <= 3'b100;
        end else begin
            prev_stage <= dut.u_core.execution_stage;
        end
    end

    function automatic bit instruction_retired();
        instruction_retired =
            (prev_stage == STAGE_EXECUTE_SINGLE) ||
            (prev_stage == STAGE_EXECUTE_DOUBLE);
    endfunction

    function automatic bit breakpoint_hit();
        breakpoint_hit = breakpoints[dut.u_core.pc_bus];
    endfunction

    task automatic reset_counters_and_status();
        begin
            cycle_count = 0;
            instruction_count = 0;
            halt_repeat_count = 0;
            last_stop_reason = STOP_NONE;
            halted = 1'b0;
            quit_requested = 1'b0;
        end
    endtask

    task automatic do_reset_sequence();
        begin
            reset = 1'b0;
            reset_counters_and_status();
            repeat (DEFAULT_RESET_CYCLES) @(posedge clk);
            reset = 1'b1;
            @(negedge clk);
        end
    endtask

    task automatic execute_one_cycle(output bit retired, output int stop_reason);
        logic [15:0] retired_ir;
        begin
            retired = 1'b0;
            stop_reason = STOP_NONE;

            @(posedge clk);
            cycle_count = cycle_count + 1;
            #1;

            if (instruction_retired()) begin
                retired = 1'b1;
                instruction_count = instruction_count + 1;
                retired_ir = dut.u_core.instruction;
                if (retired_ir == 16'h40FF) begin
                    halt_repeat_count = halt_repeat_count + 1;
                end else begin
                    halt_repeat_count = 0;
                end
                if (halt_repeat_count >= HALT_REPEAT_THRESHOLD) begin
                    halted = 1'b1;
                    stop_reason = STOP_HALTED;
                end
            end

            if (stop_reason == STOP_NONE && breakpoint_hit()) begin
                stop_reason = STOP_BREAKPOINT;
            end

            if (stop_reason == STOP_NONE && cycle_count >= max_cycles) begin
                stop_reason = STOP_TIMEOUT;
            end

            if (stop_reason != STOP_NONE) begin
                last_stop_reason = stop_reason;
            end
        end
    endtask

    task sv_init;
        begin
            clk = 1'b0;
            reset = 1'b0;
            sel = 2'b00;
            reg_sel = 4'h0;
            prev_stage = 3'b100;
            current_mem_file = DEFAULT_MEM_FILE;
            max_cycles = DEFAULT_MAX_CYCLES;
            wave_enabled = 1'b0;
            wave_initialized = 1'b0;
            for (int i = 0; i < 65536; i++) begin
                breakpoints[i] = 1'b0;
            end
            u_mem.load_hex(current_mem_file);
            do_reset_sequence();
        end
    endtask

    task sv_reset;
        begin
            do_reset_sequence();
        end
    endtask

    task sv_step_cycles(input int n);
        bit retired;
        int stop_reason;
        int target;
        begin
            if (n <= 0) begin
                last_stop_reason = STOP_STEP;
            end else begin
                target = n;
                last_stop_reason = STOP_NONE;
                for (int i = 0; i < target; i++) begin
                    execute_one_cycle(retired, stop_reason);
                    if (stop_reason != STOP_NONE) begin
                        return;
                    end
                end
                last_stop_reason = STOP_STEP;
            end
        end
    endtask

    task sv_step_instructions(input int n);
        bit retired;
        int stop_reason;
        int retired_target;
        int retired_seen;
        begin
            retired_seen = 0;
            retired_target = (n <= 0) ? 1 : n;
            last_stop_reason = STOP_NONE;
            while (retired_seen < retired_target) begin
                execute_one_cycle(retired, stop_reason);
                if (retired) begin
                    retired_seen++;
                end
                if (stop_reason != STOP_NONE) begin
                    return;
                end
            end
            last_stop_reason = STOP_STEP;
        end
    endtask

    task automatic run_until_stop();
        bit retired;
        int stop_reason;
        begin
            last_stop_reason = STOP_NONE;
            while (1) begin
                execute_one_cycle(retired, stop_reason);
                if (stop_reason != STOP_NONE) begin
                    return;
                end
            end
        end
    endtask

    task sv_run;
        begin
            run_until_stop();
        end
    endtask

    task sv_continue;
        begin
            run_until_stop();
        end
    endtask

    task sv_quit;
        begin
            quit_requested = 1'b1;
            last_stop_reason = STOP_QUIT;
        end
    endtask

    function int sv_read_reg(input int id);
        if (id < 0 || id > 15) begin
            sv_read_reg = 32'hFFFF_FFFF;
        end else begin
            sv_read_reg = {16'h0000, dut.u_core.u_reg_file.regs[id]};
        end
    endfunction

    function int sv_read_pc();
        sv_read_pc = {16'h0000, dut.u_core.pc_bus};
    endfunction

    function int sv_read_mem(input int addr);
        if (addr < 0 || addr > 16'hFFFF) begin
            sv_read_mem = 32'hFFFF_FFFF;
        end else begin
            sv_read_mem = {16'h0000, u_mem.mem[addr[15:0]]};
        end
    endfunction

    function int sv_get_cycle_count();
        sv_get_cycle_count = cycle_count;
    endfunction

    function int sv_get_instr_count();
        sv_get_instr_count = instruction_count;
    endfunction

    function int sv_is_halted();
        sv_is_halted = halted ? 1 : 0;
    endfunction

    function int sv_get_last_stop_reason();
        sv_get_last_stop_reason = last_stop_reason;
    endfunction

    task sv_add_breakpoint(input int pc_addr);
        begin
            if (pc_addr >= 0 && pc_addr <= 16'hFFFF) begin
                breakpoints[pc_addr[15:0]] = 1'b1;
            end
        end
    endtask

    task sv_clear_breakpoints;
        begin
            for (int i = 0; i < 65536; i++) begin
                breakpoints[i] = 1'b0;
            end
        end
    endtask

    task sv_load_hex(input string path, output int status);
        begin
            current_mem_file = path;
            u_mem.load_hex(current_mem_file);
            do_reset_sequence();
            status = 1;
        end
    endtask

    function int sv_wave_set(input int enable);
        begin
            if (enable != 0) begin
                if (!wave_initialized) begin
                    $vcdplusfile(WAVE_FILE);
                    wave_initialized = 1'b1;
                end
                $vcdpluson;
                wave_enabled = 1'b1;
            end else begin
                if (wave_initialized) begin
                    $vcdplusoff;
                end
                wave_enabled = 1'b0;
            end
            sv_wave_set = wave_enabled ? 1 : 0;
        end
    endfunction

    initial begin
        void'($system("mkdir -p build/waves"));
        sv_init();
        debugger_main();
        if (!quit_requested) begin
            sv_quit();
        end
        $finish;
    end
endmodule
