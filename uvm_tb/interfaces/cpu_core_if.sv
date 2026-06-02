interface cpu_core_if(input logic clk);
    localparam int MEM_DEPTH = 65536;
    localparam logic [2:0] STAGE_EXECUTE_SINGLE = 3'b011;
    localparam logic [2:0] STAGE_EXECUTE_DOUBLE = 3'b111;
    localparam logic [2:0] STAGE_LOAD_CALL_TARGET = 3'b110;
    localparam logic [2:0] STAGE_FETCH_DECODE = 3'b001;
    localparam logic [2:0] STAGE_FETCH_SECOND_WORD = 3'b101;

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
    logic [15:0] current_seq_pc;
    logic [15:0] prev_dbg_pc;
    logic [15:0] prev_dbg_ir;
    logic        prev_c;
    logic        prev_z;
    logic        prev_v;
    logic        prev_s;
    int unsigned halt_loop_count;

    assign data_bus = (reset && (wr === 1'b1)) ? mem[address_bus] : 16'hzzzz;

    task automatic init_signals();
        reset         = 1'b0;
        sel           = 2'b00;
        reg_sel       = 4'h0;
        prev_exec_stage = 3'b100;
        current_seq_pc = 16'h0000;
        prev_dbg_pc    = 16'h0000;
        prev_dbg_ir    = 16'h0000;
        prev_c         = 1'b0;
        prev_z         = 1'b0;
        prev_v         = 1'b0;
        prev_s         = 1'b0;
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
            current_seq_pc <= 16'h0000;
        end else begin
            prev_exec_stage <= exec_stage;
            if ((exec_stage == STAGE_FETCH_DECODE) || (exec_stage == STAGE_FETCH_SECOND_WORD)) begin
                current_seq_pc <= dbg_pc;
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

            if ((prev_exec_stage == STAGE_EXECUTE_SINGLE) || (prev_exec_stage == STAGE_EXECUTE_DOUBLE) || (prev_exec_stage == STAGE_LOAD_CALL_TARGET)) begin
                logic [7:0] opcode;
                opcode = dbg_ir[15:8];

                case (opcode)
                    8'hF0: begin
                        if ((c !== prev_c) || (z !== prev_z) || (v !== prev_v) || (s !== prev_s)) begin
                            $error("[cpu_core_if] CALLA modified flags unexpectedly");
                        end
                    end
                    8'hF1: begin
                        if ((c !== prev_c) || (z !== prev_z) || (v !== prev_v) || (s !== prev_s)) begin
                            $error("[cpu_core_if] RET modified flags unexpectedly");
                        end
                    end
                    default: begin end
                endcase
            end

            prev_dbg_pc <= dbg_pc;
            prev_dbg_ir <= dbg_ir;
            prev_c <= c;
            prev_z <= z;
            prev_v <= v;
            prev_s <= s;
        end
    end
endinterface
