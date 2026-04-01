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
    inout  wire [15:0] data_bus,
    output logic [15:0] address_bus,
    output logic [15:0] reg_data
);
    localparam logic [1:0] ADDRESS_FROM_PC  = 2'b01;
    localparam logic [1:0] ADDRESS_FROM_ALU = 2'b11;

    logic alu_carry_flag;
    logic alu_zero_flag;
    logic alu_overflow_flag;
    logic alu_sign_flag;
    logic carry_flag;
    logic zero_flag;
    logic overflow_flag;
    logic sign_flag;
    logic pc_write_enable;
    logic reg_write_enable;
    logic alu_cin;
    logic memory_write_enable;
    logic [1:0] sst;
    logic [1:0] carry_in_select;
    logic [1:0] address_write_select;
    logic [2:0] execution_stage;
    logic [3:0] alu_func;
    logic [2:0] alu_in_sel;
    logic [3:0] d_reg;
    logic [3:0] s_reg;
    logic [7:0] offset_8;
    logic [15:0] instruction;
    logic [15:0] alu_operand_a;
    logic [15:0] alu_operand_b;
    logic [15:0] alu_out;
    logic [15:0] reg_test;
    logic [15:0] offset_16;
    logic [15:0] pc_bus;
    logic [15:0] mem_data;
    logic [15:0] reg_inout;
    logic [15:0] sr;
    logic [15:0] dr;
    logic        instruction_load_enable;

    controller u_controller (
        .execution_stage(execution_stage),
        .instruction(instruction),
        .c(carry_flag),
        .z(zero_flag),
        .v(overflow_flag),
        .s(sign_flag),
        .dest_reg(d_reg),
        .sour_reg(s_reg),
        .offset(offset_8),
        .sst(sst),
        .carry_in_select(carry_in_select),
        .address_write_select(address_write_select),
        .instruction_load_enable(instruction_load_enable),
        .alu_func(alu_func),
        .alu_in_sel(alu_in_sel),
        .reg_write_enable(reg_write_enable),
        .pc_write_enable(pc_write_enable),
        .wr(memory_write_enable)
    );

    assign wr = memory_write_enable;
    assign c  = carry_flag;
    assign z  = zero_flag;
    assign v  = overflow_flag;
    assign s  = sign_flag;

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
        .c(alu_carry_flag),
        .z(alu_zero_flag),
        .v(alu_overflow_flag),
        .s(alu_sign_flag)
    );

    flag_reg u_flag_reg (
        .sst(sst),
        .next_carry_flag(alu_carry_flag),
        .next_zero_flag(alu_zero_flag),
        .next_overflow_flag(alu_overflow_flag),
        .next_sign_flag(alu_sign_flag),
        .clk(clk),
        .reset(reset),
        .carry_flag(carry_flag),
        .zero_flag(zero_flag),
        .overflow_flag(overflow_flag),
        .sign_flag(sign_flag)
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
        .address_write_select(address_write_select),
        .instruction_load_enable(instruction_load_enable),
        .pc_en(pc_write_enable),
        .reg_en(reg_write_enable),
        .q(reg_test)
    );

    instruction_reg u_instruction_reg (
        .memory_data(mem_data),
        .load_enable(instruction_load_enable),
        .clk(clk),
        .reset_n(reset),
        .instruction(instruction)
    );

    t1 u_carry_in_mux (
        .flag_c(carry_flag),
        .carry_in_select(carry_in_select),
        .alu_cin(alu_cin)
    );

    t2 u_offset_ext (
        .offset_8(offset_8),
        .offset_16(offset_16)
    );

    assign data_bus = (memory_write_enable == 1'b0) ? alu_out : 16'hzzzz;
    assign mem_data = data_bus;

    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            address_bus <= 16'h0000;
        end else begin
            case (address_write_select)
                ADDRESS_FROM_PC:  address_bus <= pc_bus;
                ADDRESS_FROM_ALU: address_bus <= alu_out;
                default: begin
                end
            endcase
        end
    end

    pc u_pc (
        .alu_out(alu_out),
        .en(pc_write_enable),
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
        .write_en(reg_write_enable),
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
