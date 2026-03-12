module bus_mux (
    input  logic [2:0]  alu_in_sel,
    input  logic [15:0] data,
    input  logic [15:0] pc,
    input  logic [15:0] offset,
    input  logic [15:0] sr,
    input  logic [15:0] dr,
    output logic [15:0] alu_sr,
    output logic [15:0] alu_dr
);
    always_comb begin
        case (alu_in_sel)
            3'b000: begin
                alu_sr = sr;
                alu_dr = dr;
            end
            3'b001: begin
                alu_sr = sr;
                alu_dr = 16'h0000;
            end
            3'b010: begin
                alu_sr = 16'h0000;
                alu_dr = dr;
            end
            3'b011: begin
                alu_sr = offset;
                alu_dr = pc;
            end
            3'b100: begin
                alu_sr = 16'h0000;
                alu_dr = pc;
            end
            3'b101: begin
                alu_sr = 16'h0000;
                alu_dr = data;
            end
            default: begin
                alu_sr = 16'h0000;
                alu_dr = 16'h0000;
            end
        endcase
    end
endmodule
