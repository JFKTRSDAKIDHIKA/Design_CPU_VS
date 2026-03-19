module reg_out (
    input  logic [15:0] ir,
    input  logic [15:0] pc,
    input  logic [15:0] reg_in,
    input  logic [15:0] offset,
    input  logic [15:0] alu_a,
    input  logic [15:0] alu_b,
    input  logic [15:0] alu_out,
    input  logic [15:0] reg_testa,
    input  logic [3:0]  reg_sel,
    input  logic [1:0]  sel,
    output logic [15:0] reg_data
);
    always_comb begin
        case (sel)
            2'b00: reg_data = reg_in;
            2'b01: begin
                case (reg_sel)
                    4'h0: reg_data = offset;
                    4'h1: reg_data = alu_a;
                    4'h2: reg_data = alu_b;
                    4'h3: reg_data = alu_out;
                    4'h4: reg_data = reg_testa;
                    default: reg_data = 16'h0000;
                endcase
            end
            2'b11: begin
                case (reg_sel)
                    4'hE: reg_data = pc;
                    4'hF: reg_data = ir;
                    default: reg_data = 16'h0000;
                endcase
            end
            default: reg_data = 16'h0000;
        endcase
    end
endmodule
