module alu (
    input  logic        cin,
    input  logic [15:0] alu_a,
    input  logic [15:0] alu_b,
    input  logic [2:0]  alu_func,
    output logic [15:0] alu_out,
    output logic        c,
    output logic        z,
    output logic        v,
    output logic        s
);
    logic [15:0] temp1;
    logic [15:0] temp2;
    logic [15:0] temp3;
    integer i;

    always_comb begin
        temp1 = {15'b0, cin};
        temp2 = 16'h0000;
        temp3 = 16'h0000;

        case (alu_func)
            3'b000: temp2 = $unsigned(alu_b) + $unsigned(alu_a) + $unsigned(temp1);
            3'b001: temp2 = $unsigned(alu_b) - $unsigned(alu_a) - $unsigned(temp1);
            3'b010: temp2 = alu_a & alu_b;
            3'b011: temp2 = alu_a | alu_b;
            3'b100: temp2 = alu_a ^ alu_b;
            3'b101: begin
                temp2[0] = 1'b0;
                for (i = 15; i >= 1; i = i - 1) begin
                    temp2[i] = alu_b[i-1];
                end
            end
            3'b110: begin
                temp2[15] = 1'b0;
                for (i = 14; i >= 0; i = i - 1) begin
                    temp2[i] = alu_b[i+1];
                end
            end
            default: temp2 = 16'h0000;
        endcase

        alu_out = temp2;
        z = (temp2 == 16'h0000);
        s = temp2[15];

        case (alu_func)
            3'b000,
            3'b001: begin
                if ((alu_a[15] == 1'b1 && alu_b[15] == 1'b1 && temp2[15] == 1'b0) ||
                    (alu_a[15] == 1'b0 && alu_b[15] == 1'b0 && temp2[15] == 1'b1)) begin
                    v = 1'b1;
                end else begin
                    v = 1'b0;
                end
            end
            default: v = 1'b0;
        endcase

        case (alu_func)
            3'b000: begin
                temp3 = $unsigned(16'hFFFF) - $unsigned(alu_b) - $unsigned(temp1);
                c = ($unsigned(temp3) < $unsigned(alu_a));
            end
            3'b001: c = ($unsigned(alu_b) < $unsigned(alu_a));
            3'b101: c = alu_b[15];
            3'b110: c = alu_b[0];
            default: c = 1'b0;
        endcase
    end
endmodule
