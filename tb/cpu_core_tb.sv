module cpu_core_tb;
    localparam logic [2:0] STAGE_EXECUTE_SINGLE = 3'b011;
    localparam logic [2:0] STAGE_EXECUTE_DOUBLE = 3'b111;
    localparam int         HALT_REPEAT_THRESHOLD = 3;
    localparam int         MAX_CYCLES = 300;

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

    string mem_file;
    string summary_file;
    string trace_file;
    string vpd_file;
    integer trace_fd;
    integer summary_fd;
    int cycle_count;
    int retire_count;
    int halt_repeat_count;
    bit finished;
    logic [15:0] last_r0;
    logic [15:0] last_r1;
    logic [15:0] last_r2;
    logic [15:0] last_r3;
    logic [15:0] last_r4;
    logic [15:0] last_pc;
    logic [15:0] last_ir;
    logic        last_c;
    logic        last_z;
    logic        last_v;
    logic        last_s;

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

    task automatic set_debug(input logic [1:0] next_sel, input logic [3:0] next_reg_sel);
        begin
            sel = next_sel;
            reg_sel = next_reg_sel;
            #1;
        end
    endtask

    task automatic peek_reg(input logic [3:0] idx, output logic [15:0] value);
        begin
            set_debug(2'b00, idx);
            value = reg_data;
        end
    endtask

    task automatic peek_pc(output logic [15:0] value);
        begin
            set_debug(2'b11, 4'hE);
            value = reg_data;
        end
    endtask

    task automatic peek_ir(output logic [15:0] value);
        begin
            set_debug(2'b11, 4'hF);
            value = reg_data;
        end
    endtask

    task automatic log_trace();
        logic [15:0] r0;
        logic [15:0] r1;
        logic [15:0] r2;
        logic [15:0] r3;
        logic [15:0] r4;
        logic [15:0] pc;
        logic [15:0] ir;
        begin
            peek_reg(4'd0, r0);
            peek_reg(4'd1, r1);
            peek_reg(4'd2, r2);
            peek_reg(4'd3, r3);
            peek_reg(4'd4, r4);
            peek_pc(pc);
            peek_ir(ir);
            $fwrite(
                trace_fd,
                "TRACE step=%0d pc=%04h ir=%04h R0=%04h R1=%04h R2=%04h R3=%04h R4=%04h C=%0d Z=%0d V=%0d S=%0d\n",
                retire_count, pc, ir, r0, r1, r2, r3, r4, c, z, v, s
            );
            last_r0 = r0;
            last_r1 = r1;
            last_r2 = r2;
            last_r3 = r3;
            last_r4 = r4;
            last_pc = pc;
            last_ir = ir;
            last_c = c;
            last_z = z;
            last_v = v;
            last_s = s;
            if (ir == 16'h40FF) begin
                halt_repeat_count++;
            end else begin
                halt_repeat_count = 0;
            end
        end
    endtask

    task automatic write_summary(input bit pass);
        logic [15:0] r0;
        logic [15:0] r1;
        logic [15:0] r2;
        logic [15:0] r3;
        logic [15:0] r4;
        logic [15:0] pc;
        logic [15:0] ir;
        begin
            if (retire_count > 0) begin
                r0 = last_r0;
                r1 = last_r1;
                r2 = last_r2;
                r3 = last_r3;
                r4 = last_r4;
                pc = last_pc;
                ir = last_ir;
            end else begin
                peek_reg(4'd0, r0);
                peek_reg(4'd1, r1);
                peek_reg(4'd2, r2);
                peek_reg(4'd3, r3);
                peek_reg(4'd4, r4);
                peek_pc(pc);
                peek_ir(ir);
            end
            summary_fd = $fopen(summary_file, "w");
            if (summary_fd == 0) begin
                $fatal(1, "[tb] failed to open summary file %s", summary_file);
            end
            $fwrite(summary_fd, "result=%s\n", pass ? "PASS" : "FAIL");
            $fwrite(summary_fd, "cycles=%0d\n", cycle_count);
            $fwrite(summary_fd, "retire_count=%0d\n", retire_count);
            $fwrite(summary_fd, "pc=0x%04h\n", pc);
            $fwrite(summary_fd, "ir=0x%04h\n", ir);
            $fwrite(summary_fd, "r0=0x%04h\n", r0);
            $fwrite(summary_fd, "r1=0x%04h\n", r1);
            $fwrite(summary_fd, "r2=0x%04h\n", r2);
            $fwrite(summary_fd, "r3=0x%04h\n", r3);
            $fwrite(summary_fd, "r4=0x%04h\n", r4);
            $fwrite(summary_fd, "c=%0d\n", retire_count > 0 ? last_c : c);
            $fwrite(summary_fd, "z=%0d\n", retire_count > 0 ? last_z : z);
            $fwrite(summary_fd, "v=%0d\n", retire_count > 0 ? last_v : v);
            $fwrite(summary_fd, "s=%0d\n", retire_count > 0 ? last_s : s);
            $fclose(summary_fd);
        end
    endtask

    task automatic finish_pass();
        logic [15:0] r0;
        logic [15:0] r1;
        logic [15:0] r2;
        logic [15:0] r3;
        begin
            peek_reg(4'd0, r0);
            peek_reg(4'd1, r1);
            peek_reg(4'd2, r2);
            peek_reg(4'd3, r3);
            if (r2 !== 16'd150) begin
                $error("[tb] Expected R2=150, got %0d (0x%04h)", r2, r2);
                write_summary(1'b0);
                $finish(1);
            end
            if (r1 !== 16'd0) begin
                $error("[tb] Expected R1=0, got %0d (0x%04h)", r1, r1);
                write_summary(1'b0);
                $finish(1);
            end
            if (r3 !== 16'd0) begin
                $error("[tb] Expected R3=0, got %0d (0x%04h)", r3, r3);
                write_summary(1'b0);
                $finish(1);
            end
            $display("[tb] PASS cycles=%0d retires=%0d R0=%0d R1=%0d R2=%0d R3=%0d", cycle_count, retire_count, r0, r1, r2, r3);
            write_summary(1'b1);
            finished = 1'b1;
            $finish;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b0;
        sel = 2'b00;
        reg_sel = 4'h0;
        prev_stage = 3'b100;
        cycle_count = 0;
        retire_count = 0;
        halt_repeat_count = 0;
        finished = 1'b0;
        last_r0 = '0;
        last_r1 = '0;
        last_r2 = '0;
        last_r3 = '0;
        last_r4 = '0;
        last_pc = '0;
        last_ir = '0;
        last_c = 1'b0;
        last_z = 1'b0;
        last_v = 1'b0;
        last_s = 1'b0;

        if (!$value$plusargs("mem=%s", mem_file)) begin
            mem_file = "sw/mult8.hex";
        end
        if (!$value$plusargs("summary=%s", summary_file)) begin
            summary_file = "logs/rtl_summary.txt";
        end
        if (!$value$plusargs("trace=%s", trace_file)) begin
            trace_file = "logs/rtl_trace.txt";
        end
        if ($value$plusargs("vpd=%s", vpd_file)) begin
            $vcdplusfile(vpd_file);
            $vcdpluson(0, cpu_core_tb);
        end

        trace_fd = $fopen(trace_file, "w");
        if (trace_fd == 0) begin
            $fatal(1, "[tb] failed to open trace file %s", trace_file);
        end

        u_mem.load_hex(mem_file);

        repeat (2) @(posedge clk);
        reset = 1'b1;
    end

    always @(negedge clk or negedge reset) begin
        if (!reset) begin
            prev_stage <= 3'b100;
        end else begin
            prev_stage <= dut.u_core.execution_stage;
        end
    end

    always @(posedge clk) begin
        if (!reset || finished) begin
            if (!reset) begin
                cycle_count <= 0;
            end
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    always @(posedge clk) begin
        if (!reset || finished) begin
            // no-op
        end else begin
            #1;
            if (prev_stage == STAGE_EXECUTE_SINGLE || prev_stage == STAGE_EXECUTE_DOUBLE) begin
                retire_count++;
                log_trace();
                if (halt_repeat_count >= HALT_REPEAT_THRESHOLD) begin
                    finish_pass();
                end
            end

            if (cycle_count >= MAX_CYCLES) begin
                $error("[tb] Timeout after %0d cycles", cycle_count);
                write_summary(1'b0);
                $finish(1);
            end
        end
    end

    final begin
        if (trace_fd != 0) begin
            $fclose(trace_fd);
        end
    end
endmodule
