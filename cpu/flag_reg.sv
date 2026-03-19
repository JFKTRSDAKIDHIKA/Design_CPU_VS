module flag_reg (
    input  logic [1:0] sst,
    input  logic       next_carry_flag,
    input  logic       next_zero_flag,
    input  logic       next_overflow_flag,
    input  logic       next_sign_flag,
    input  logic       clk,
    input  logic       reset,
    output logic       carry_flag,
    output logic       zero_flag,
    output logic       overflow_flag,
    output logic       sign_flag
);
    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            carry_flag    <= 1'b0;
            zero_flag     <= 1'b0;
            overflow_flag <= 1'b0;
            sign_flag     <= 1'b0;
        end else begin
            case (sst)
                2'b00: begin
                    carry_flag    <= next_carry_flag;
                    zero_flag     <= next_zero_flag;
                    overflow_flag <= next_overflow_flag;
                    sign_flag     <= next_sign_flag;
                end
                2'b01: carry_flag <= 1'b0;
                2'b10: carry_flag <= 1'b1;
                2'b11: begin
                end
            endcase
        end
    end
endmodule
