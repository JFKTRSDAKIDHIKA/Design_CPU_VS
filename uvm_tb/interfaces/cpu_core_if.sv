interface cpu_core_if(input logic clk);
    localparam int MEM_DEPTH = 65536;
    localparam logic [2:0] STAGE_EXECUTE_SINGLE = 3'b011;
    localparam logic [2:0] STAGE_EXECUTE_DOUBLE = 3'b111;

    logic        reset;
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
    logic [2:0]  exec_stage;
    logic [15:0] dbg_pc;
    logic [15:0] dbg_ir;

    logic [15:0] mem [0:MEM_DEPTH-1];
    logic [2:0]  prev_exec_stage;
    logic [15:0] retire_instr_addr;
    logic [15:0] prev_dbg_pc;
    logic [15:0] prev_dbg_ir;
    int unsigned halt_loop_count;

    assign data_bus = (reset && (wr === 1'b1)) ? mem[address_bus] : 16'hzzzz;

    task automatic init_signals();
        reset         = 1'b0;
        sel           = 2'b00;
        reg_sel       = 4'h0;
        prev_exec_stage = 3'b100;
        retire_instr_addr = 16'h0000;
        prev_dbg_pc    = 16'h0000;
        prev_dbg_ir    = 16'h0000;
        halt_loop_count = 0;
    endtask

    task automatic clear_memory();
        for (int idx = 0; idx < MEM_DEPTH; idx++) begin
            mem[idx] = 16'h0000;
        end
    endtask

    task automatic load_hex(input string mem_file);
        clear_memory();
        $display("[cpu_core_if] loading %s", mem_file);
        $readmemh(mem_file, mem);
    endtask

    task automatic commit_write_if_needed();
        if (reset && (wr === 1'b0)) begin
            mem[address_bus] = data_bus;
        end
    endtask

    task automatic peek_reg(input int idx, output logic [15:0] value);
        sel     <= 2'b00;
        reg_sel <= idx[3:0];
        #1step;
        value = reg_data;
    endtask

    task automatic peek_pc(output logic [15:0] value);
        sel     <= 2'b11;
        reg_sel <= 4'hE;
        #1step;
        value = reg_data;
    endtask

    task automatic peek_ir(output logic [15:0] value);
        sel     <= 2'b11;
        reg_sel <= 4'hF;
        #1step;
        value = reg_data;
    endtask

    task automatic sample_state(
        output logic [15:0] regs[16],
        output logic [15:0] pc,
        output logic [15:0] ir,
        output logic        out_c,
        output logic        out_z,
        output logic        out_v,
        output logic        out_s
    );
        for (int idx = 0; idx < 16; idx++) begin
            peek_reg(idx, regs[idx]);
        end
        peek_pc(pc);
        peek_ir(ir);
        out_c = c;
        out_z = z;
        out_v = v;
        out_s = s;
    endtask

    function automatic logic [15:0] sign_extend8(input logic [7:0] value);
        return {{8{value[7]}}, value};
    endfunction

    always @(negedge clk) begin
        if (!reset) begin
            prev_exec_stage <= 3'b100;
            retire_instr_addr <= 16'h0000;
        end else begin
            prev_exec_stage <= exec_stage;
            if (exec_stage == 3'b000) begin
                retire_instr_addr <= address_bus;
            end
        end
    end

    always @(posedge clk) begin
        if (!reset) begin
            prev_dbg_pc <= 16'h0000;
            prev_dbg_ir <= 16'h0000;
            halt_loop_count <= 0;
        end else begin
            if ((wr !== 1'b0) && (wr !== 1'b1)) begin
                $error("[cpu_core_if] wr became X/Z while reset is active");
            end
            if ((wr === 1'b1) && (data_bus === 16'hzzzz)) begin
                $error("[cpu_core_if] read cycle observed undriven data_bus");
            end
            if ((wr === 1'b0) && ((data_bus === 16'hzzzz) || (^data_bus === 1'bx))) begin
                $error("[cpu_core_if] write cycle observed invalid DUT data_bus drive");
            end
            if (^address_bus === 1'bx) begin
                $error("[cpu_core_if] address_bus contains X while reset is active");
            end

            if ((prev_exec_stage == STAGE_EXECUTE_SINGLE) || (prev_exec_stage == STAGE_EXECUTE_DOUBLE)) begin
                logic [7:0] opcode;
                logic [15:0] expected_pc;
                opcode = dbg_ir[15:8];
                expected_pc = retire_instr_addr + ((opcode inside {8'h80, 8'h81}) ? 16'h0002 : 16'h0001);

                case (opcode)
                    8'h40: begin
                        if (dbg_pc !== ((retire_instr_addr + 16'h0001 + sign_extend8(dbg_ir[7:0])) & 16'hFFFF)) begin
                            $error("[cpu_core_if] JR PC update mismatch");
                        end
                    end
                    8'h41: begin
                        if (s && (dbg_pc !== ((retire_instr_addr + 16'h0001 + sign_extend8(dbg_ir[7:0])) & 16'hFFFF))) begin
                            $error("[cpu_core_if] JRS taken PC update mismatch");
                        end
                        if (!s && (dbg_pc !== expected_pc)) begin
                            $error("[cpu_core_if] JRS not-taken PC update mismatch");
                        end
                    end
                    8'h43: begin
                        if (!s && (dbg_pc !== ((retire_instr_addr + 16'h0001 + sign_extend8(dbg_ir[7:0])) & 16'hFFFF))) begin
                            $error("[cpu_core_if] JRNS taken PC update mismatch");
                        end
                        if (s && (dbg_pc !== expected_pc)) begin
                            $error("[cpu_core_if] JRNS not-taken PC update mismatch");
                        end
                    end
                    8'h44: begin
                        if (c && (dbg_pc !== ((retire_instr_addr + 16'h0001 + sign_extend8(dbg_ir[7:0])) & 16'hFFFF))) begin
                            $error("[cpu_core_if] JRC taken PC update mismatch");
                        end
                        if (!c && (dbg_pc !== expected_pc)) begin
                            $error("[cpu_core_if] JRC not-taken PC update mismatch");
                        end
                    end
                    8'h45: begin
                        if (!c && (dbg_pc !== ((retire_instr_addr + 16'h0001 + sign_extend8(dbg_ir[7:0])) & 16'hFFFF))) begin
                            $error("[cpu_core_if] JRNC taken PC update mismatch");
                        end
                        if (c && (dbg_pc !== expected_pc)) begin
                            $error("[cpu_core_if] JRNC not-taken PC update mismatch");
                        end
                    end
                    8'h46: begin
                        if (z && (dbg_pc !== ((retire_instr_addr + 16'h0001 + sign_extend8(dbg_ir[7:0])) & 16'hFFFF))) begin
                            $error("[cpu_core_if] JRZ taken PC update mismatch");
                        end
                        if (!z && (dbg_pc !== expected_pc)) begin
                            $error("[cpu_core_if] JRZ not-taken PC update mismatch");
                        end
                    end
                    8'h47: begin
                        if (!z && (dbg_pc !== ((retire_instr_addr + 16'h0001 + sign_extend8(dbg_ir[7:0])) & 16'hFFFF))) begin
                            $error("[cpu_core_if] JRNZ taken PC update mismatch");
                        end
                        if (z && (dbg_pc !== expected_pc)) begin
                            $error("[cpu_core_if] JRNZ not-taken PC update mismatch");
                        end
                    end
                    8'h80: begin
                        if (dbg_pc !== mem[(retire_instr_addr + 16'h0001) & 16'hFFFF]) begin
                            $error("[cpu_core_if] JMPA PC update mismatch");
                        end
                    end
                    8'h81: begin
                        if (dbg_pc !== (retire_instr_addr + 16'h0002)) begin
                            $error("[cpu_core_if] MVRD did not advance PC by 2");
                        end
                    end
                    default: begin end
                endcase
            end

            if (dbg_ir == 16'h40FF) begin
                if ((prev_dbg_ir == 16'h40FF) && (dbg_pc !== prev_dbg_pc)) begin
                    $error("[cpu_core_if] HALT self-loop changed PC unexpectedly");
                end
                halt_loop_count <= halt_loop_count + 1;
            end else begin
                halt_loop_count <= 0;
            end

            prev_dbg_pc <= dbg_pc;
            prev_dbg_ir <= dbg_ir;
        end
    end
endinterface
