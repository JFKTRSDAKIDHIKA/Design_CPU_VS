module ar (
    input  logic [15:0] alu_out,
    input  logic [15:0] pc,
    input  logic [1:0]  rec,
    input  logic        clk,
    input  logic        reset,
    output logic [15:0] q
);
    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            q <= 16'h0000;
        end else begin
            case (rec)
                2'b01: q <= pc;
                2'b11: q <= alu_out;
                default: begin
                    // hold
                end
            endcase
        end
    end
endmodule
