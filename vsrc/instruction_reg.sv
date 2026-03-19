module instruction_reg (
    input  logic [15:0] memory_data,
    input  logic        load_enable,
    input  logic        clk,
    input  logic        reset_n,
    output logic [15:0] instruction
);
    always_ff @(posedge clk or negedge reset_n) begin
        if (reset_n == 1'b0) begin
            instruction <= 16'h0000;
        end else if (load_enable == 1'b1) begin
            instruction <= memory_data;
        end
    end
endmodule
