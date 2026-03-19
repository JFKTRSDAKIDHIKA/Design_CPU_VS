module cpu_core (
    input  logic        reset,
    input  logic        clk,
    output logic        wr,
    output logic        c,
    output logic        z,
    output logic        v,
    output logic        s,
    input  logic [1:0]  sel,
    input  logic [3:0]  reg_sel,
    inout  logic [15:0] data_bus,
    output logic [15:0] address_bus,
    output logic [15:0] reg_data
);
    localparam logic [1:0] STATE_WRITE_HOLD = 2'b00;
    localparam logic [1:0] STATE_WRITE_PC   = 2'b01;
    localparam logic [1:0] STATE_WRITE_IR   = 2'b10;
    localparam logic [1:0] STATE_WRITE_ALU  = 2'b11;

    logic fc, fz, fv, fs, flag_c, flag_z, flag_v, flag_s, en_pc, en_reg, alu_cin;
    logic wre;
    logic [1:0] sst, sci, state_write_select;
    logic [2:0] execution_stage, alu_func, alu_in_sel;
    logic [3:0] d_reg, s_reg;
    logic [7:0] offset_8;
    logic [15:0] instruction, alu_operand_a, alu_operand_b, alu_out, reg_test, offset_16, pc_bus, mem_data;
    logic [15:0] reg_inout, sr, dr;
    logic        instruction_load_enable;

    controller u_controller (
        .execution_stage(execution_stage),
        .instruction(instruction),
        .c(flag_c),
        .z(flag_z),
        .v(flag_v),
        .s(flag_s),
        .dest_reg(d_reg),
        .sour_reg(s_reg),
        .offset(offset_8),
        .sst(sst),
        .sci(sci),
        .state_write_select(state_write_select),
        .alu_func(alu_func),
        .alu_in_sel(alu_in_sel),
        .en_reg(en_reg),
        .en_pc(en_pc),
        .wr(wre)
    );

    always_comb begin
        wr = wre;
        c = flag_c;
        z = flag_z;
        v = flag_v;
        s = flag_s;
    end

    alu u_alu (
        .cin(alu_cin),
        .alu_in_sel(alu_in_sel),
        .memory_data(mem_data),
        .pc_value(pc_bus),
        .offset_value(offset_16),
        .source_reg_value(sr),
        .dest_reg_value(dr),
        .alu_func(alu_func),
        .operand_a(alu_operand_a),
        .operand_b(alu_operand_b),
        .alu_out(alu_out),
        .c(fc),
        .z(fz),
        .v(fv),
        .s(fs)
    );

    flag_reg u_flag_reg (
        .sst(sst),
        .c(fc),
        .z(fz),
        .v(fv),
        .s(fs),
        .clk(clk),
        .reset(reset),
        .flag_c(flag_c),
        .flag_z(flag_z),
        .flag_v(flag_v),
        .flag_s(flag_s)
    );

    execution_stage_fsm u_execution_stage_fsm (
        .clk(clk),
        .reset(reset),
        .inst(mem_data),
        .stage_code(execution_stage)
    );

    reg_testa u_trace_reg (
        .clk(clk),
        .reset(reset),
        .input_a(execution_stage),
        .input_b(alu_func),
        .input_c(alu_in_sel),
        .cin(alu_cin),
        .state_write_select(state_write_select),
        .pc_en(en_pc),
        .reg_en(en_reg),
        .q(reg_test)
    );

    assign instruction_load_enable = (state_write_select == STATE_WRITE_IR);

    instruction_reg u_instruction_reg (
        .memory_data(mem_data),
        .load_enable(instruction_load_enable),
        .clk(clk),
        .reset_n(reset),
        .instruction(instruction)
    );

    t1 u_carry_in_mux (
        .flag_c(flag_c),
        .sci(sci),
        .alu_cin(alu_cin)
    );

    t2 u_offset_ext (
        .offset_8(offset_8),
        .offset_16(offset_16)
    );

    bus_dir u_bus_dir (
        .wr(wre),
        .alu_out(alu_out),
        .data_bus(data_bus),
        .mem_data(mem_data)
    );

    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            address_bus <= 16'h0000;
        end else begin
            case (state_write_select)
                STATE_WRITE_PC:  address_bus <= pc_bus;
                STATE_WRITE_ALU: address_bus <= alu_out;
                default: begin
                end
            endcase
        end
    end

    pc u_pc (
        .alu_out(alu_out),
        .en(en_pc),
        .clk(clk),
        .reset(reset),
        .q(pc_bus)
    );

    reg_out u_debug_mux (
        .ir(instruction),
        .pc(pc_bus),
        .reg_in(reg_inout),
        .offset(offset_16),
        .alu_a(alu_operand_a),
        .alu_b(alu_operand_b),
        .alu_out(alu_out),
        .reg_testa(reg_test),
        .reg_sel(reg_sel),
        .sel(sel),
        .reg_data(reg_data)
    );

    reg_file u_reg_file (
        .clk(clk),
        .reset(reset),
        .write_en(en_reg),
        .write_sel(d_reg),
        .dest_sel(d_reg),
        .source_sel(s_reg),
        .debug_sel(reg_sel),
        .write_data(alu_out),
        .dest_data(dr),
        .source_data(sr),
        .debug_data(reg_inout)
    );
endmodule
