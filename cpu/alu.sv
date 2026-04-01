module alu (
    input  logic        cin,
    input  logic [2:0]  alu_in_sel,
    input  logic [15:0] memory_data,
    input  logic [15:0] pc_value,
    input  logic [15:0] offset_value,
    input  logic [15:0] source_reg_value,
    input  logic [15:0] dest_reg_value,
    input  logic [3:0]  alu_func,
    output logic [15:0] operand_a,
    output logic [15:0] operand_b,
    output logic [15:0] alu_out,
    output logic        c,
    output logic        z,
    output logic        v,
    output logic        s
);
    localparam logic [2:0] ALU_IN_REGS     = 3'b000;
    localparam logic [2:0] ALU_IN_SR       = 3'b001;
    localparam logic [2:0] ALU_IN_DR       = 3'b010;
    localparam logic [2:0] ALU_IN_BR       = 3'b011;
    localparam logic [2:0] ALU_IN_PC       = 3'b100;
    localparam logic [2:0] ALU_IN_MEM      = 3'b101;
    localparam logic [2:0] ALU_IN_DR_MEM   = 3'b110;

    localparam logic [3:0] ALU_ADD         = 4'b0000;
    localparam logic [3:0] ALU_SUB         = 4'b0001;
    localparam logic [3:0] ALU_AND         = 4'b0010;
    localparam logic [3:0] ALU_OR          = 4'b0011;
    localparam logic [3:0] ALU_XOR         = 4'b0100;
    localparam logic [3:0] ALU_SHL         = 4'b0101;
    localparam logic [3:0] ALU_SHR         = 4'b0110;
    localparam logic [3:0] ALU_NOT         = 4'b0111;
    localparam logic [3:0] ALU_ASR         = 4'b1000;

    logic [16:0] add_result;
    logic [16:0] sub_result;
    logic [15:0] result_value;

    always_comb begin
        case (alu_in_sel)
            ALU_IN_REGS: begin
                operand_a = source_reg_value;
                operand_b = dest_reg_value;
            end
            ALU_IN_SR: begin
                operand_a = source_reg_value;
                operand_b = 16'h0000;
            end
            ALU_IN_DR: begin
                operand_a = 16'h0000;
                operand_b = dest_reg_value;
            end
            ALU_IN_BR: begin
                operand_a = offset_value;
                operand_b = pc_value;
            end
            ALU_IN_PC: begin
                operand_a = 16'h0000;
                operand_b = pc_value;
            end
            ALU_IN_MEM: begin
                operand_a = 16'h0000;
                operand_b = memory_data;
            end
            ALU_IN_DR_MEM: begin
                operand_a = memory_data;
                operand_b = dest_reg_value;
            end
            default: begin
                operand_a = 16'h0000;
                operand_b = 16'h0000;
            end
        endcase

        add_result = {1'b0, operand_b} + {1'b0, operand_a} + cin;
        sub_result = {1'b0, operand_b} - {1'b0, operand_a} - cin;
        result_value = 16'h0000;

        case (alu_func)
            ALU_ADD: result_value = add_result[15:0];
            ALU_SUB: result_value = sub_result[15:0];
            ALU_AND: result_value = operand_a & operand_b;
            ALU_OR:  result_value = operand_a | operand_b;
            ALU_XOR: result_value = operand_a ^ operand_b;
            ALU_SHL: result_value = {operand_b[14:0], 1'b0};
            ALU_SHR: result_value = {1'b0, operand_b[15:1]};
            ALU_NOT: result_value = ~operand_b;
            ALU_ASR: result_value = {operand_b[15], operand_b[15:1]};
            default: result_value = 16'h0000;
        endcase

        alu_out = result_value;
        z = (result_value == 16'h0000);
        s = result_value[15];

        case (alu_func)
            ALU_ADD: v = (operand_a[15] == operand_b[15]) && (result_value[15] != operand_b[15]);
            ALU_SUB: v = (operand_a[15] != operand_b[15]) && (result_value[15] != operand_b[15]);
            default: v = 1'b0;
        endcase

        case (alu_func)
            ALU_ADD: c = add_result[16];
            ALU_SUB: c = sub_result[16];
            ALU_SHL: c = operand_b[15];
            ALU_SHR: c = operand_b[0];
            ALU_ASR: c = operand_b[0];
            default: c = 1'b0;
        endcase
    end
endmodule
