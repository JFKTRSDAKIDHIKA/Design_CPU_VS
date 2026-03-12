module t3 (
    input  logic        wr,
    input  logic [15:0] alu_out,
    output logic [15:0] \output
);
    always_comb begin
        case (wr)
            1'b1: \output = 16'hzzzz;
            1'b0: \output = alu_out;
            default: \output = 16'hzzzz;
        endcase
    end
endmodule
