module pc (
    input  logic [15:0] alu_out,
    input  logic        en,
    input  logic        clk,
    input  logic        reset,
    output logic [15:0] q
);
    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            q <= 16'h0000;
        end else if (en == 1'b1) begin
            q <= alu_out;
        end
    end
endmodule
