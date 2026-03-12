module \reg (
    input  logic [15:0] d,
    input  logic        clk,
    input  logic        reset,
    input  logic        en,
    output logic [15:0] q
);
    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            q <= 16'h0000;
        end else if (en == 1'b1) begin
            q <= d;
        end
    end
endmodule
