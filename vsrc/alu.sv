module alu (
    input  logic        cin,
    input  logic [15:0] alu_a,
    input  logic [15:0] alu_b,
    input  logic [2:0]  alu_func,
    output logic [15:0] alu_out,
    output logic        c,
    output logic        z,
    output logic        v,
    output logic        s
);
    logic [16:0] add_result;
    logic [16:0] sub_result;
    logic [15:0] temp2;

    always_comb begin
        add_result = {1'b0, alu_b} + {1'b0, alu_a} + cin;
        sub_result = {1'b0, alu_b} - {1'b0, alu_a} - cin;
        temp2      = 16'h0000;

        case (alu_func)
            3'b000: temp2 = add_result[15:0];
            3'b001: temp2 = sub_result[15:0];
            3'b010: temp2 = alu_a & alu_b;
            3'b011: temp2 = alu_a | alu_b;
            3'b100: temp2 = alu_a ^ alu_b;
            3'b101: temp2 = {alu_b[14:0], 1'b0};
            3'b110: temp2 = {1'b0, alu_b[15:1]};
            default: temp2 = 16'h0000;
        endcase

        alu_out = temp2;
        z = (temp2 == 16'h0000);
        s = temp2[15];

        case (alu_func)
            3'b000: v = (alu_a[15] == alu_b[15]) && (temp2[15] != alu_b[15]);
            3'b001: v = (alu_a[15] == alu_b[15]) && (temp2[15] != alu_b[15]);
            default: v = 1'b0;
        endcase

        case (alu_func)
            3'b000: c = add_result[16];
            3'b001: c = ($unsigned(alu_b) < $unsigned(alu_a));
            3'b101: c = alu_b[15];
            3'b110: c = alu_b[0];
            default: c = 1'b0;
        endcase
    end
endmodule
