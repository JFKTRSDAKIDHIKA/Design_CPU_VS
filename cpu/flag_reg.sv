module flag_reg (
    input  logic [1:0] sst,
    input  logic       c,
    input  logic       z,
    input  logic       v,
    input  logic       s,
    input  logic       clk,
    input  logic       reset,
    output logic       flag_c,
    output logic       flag_z,
    output logic       flag_v,
    output logic       flag_s
);
    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            flag_c <= 1'b0;
            flag_z <= 1'b0;
            flag_v <= 1'b0;
            flag_s <= 1'b0;
        end else begin
            case (sst)
                2'b00: begin
                    flag_c <= c;
                    flag_z <= z;
                    flag_v <= v;
                    flag_s <= s;
                end
                2'b01: flag_c <= 1'b0;
                2'b10: flag_c <= 1'b1;
                2'b11: begin
                    // hold
                end
            endcase
        end
    end
endmodule
