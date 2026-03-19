module t1 (
    input  logic       flag_c,
    input  logic [1:0] sci,
    output logic       alu_cin
);
    always_comb begin
        case (sci)
            2'b00: alu_cin = 1'b0;
            2'b01: alu_cin = 1'b1;
            2'b10: alu_cin = flag_c;
            default: alu_cin = 1'b0;
        endcase
    end
endmodule
