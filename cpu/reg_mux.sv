module reg_mux (
    input  logic [15:0] reg_0,
    input  logic [15:0] reg_1,
    input  logic [15:0] reg_2,
    input  logic [15:0] reg_3,
    input  logic [15:0] reg_4,
    input  logic [15:0] reg_5,
    input  logic [15:0] reg_6,
    input  logic [15:0] reg_7,
    input  logic [15:0] reg_8,
    input  logic [15:0] reg_9,
    input  logic [15:0] reg_a,
    input  logic [15:0] reg_b,
    input  logic [15:0] reg_c,
    input  logic [15:0] reg_d,
    input  logic [15:0] reg_e,
    input  logic [15:0] reg_f,
    input  logic [3:0]  dest_reg,
    input  logic [3:0]  sour_reg,
    input  logic [3:0]  reg_sel,
    input  logic        en,
    output logic        en_0,
    output logic        en_1,
    output logic        en_2,
    output logic        en_3,
    output logic        en_4,
    output logic        en_5,
    output logic        en_6,
    output logic        en_7,
    output logic        en_8,
    output logic        en_9,
    output logic        en_a,
    output logic        en_b,
    output logic        en_c,
    output logic        en_d,
    output logic        en_e,
    output logic        en_f,
    output logic [15:0] dr,
    output logic [15:0] sr,
    output logic [15:0] reg_out
);
    logic [15:0] temp;

    always_comb begin
        dr   = 16'h0000;
        sr   = 16'h0000;
        temp = 16'h0000;

        case (dest_reg)
            4'h0: begin dr = reg_0; temp = 16'h0001; end
            4'h1: begin dr = reg_1; temp = 16'h0002; end
            4'h2: begin dr = reg_2; temp = 16'h0004; end
            4'h3: begin dr = reg_3; temp = 16'h0008; end
            4'h4: begin dr = reg_4; temp = 16'h0010; end
            4'h5: begin dr = reg_5; temp = 16'h0020; end
            4'h6: begin dr = reg_6; temp = 16'h0040; end
            4'h7: begin dr = reg_7; temp = 16'h0080; end
            4'h8: begin dr = reg_8; temp = 16'h0100; end
            4'h9: begin dr = reg_9; temp = 16'h0200; end
            4'hA: begin dr = reg_a; temp = 16'h0400; end
            4'hB: begin dr = reg_b; temp = 16'h0800; end
            4'hC: begin dr = reg_c; temp = 16'h1000; end
            4'hD: begin dr = reg_d; temp = 16'h2000; end
            4'hE: begin dr = reg_e; temp = 16'h4000; end
            4'hF: begin dr = reg_f; temp = 16'h8000; end
            default: begin
                // TODO: Original VHDL lacked explicit others for selector decode.
            end
        endcase

        if (en == 1'b0) begin
            temp = 16'h0000;
        end

        en_0 = temp[0];
        en_1 = temp[1];
        en_2 = temp[2];
        en_3 = temp[3];
        en_4 = temp[4];
        en_5 = temp[5];
        en_6 = temp[6];
        en_7 = temp[7];
        en_8 = temp[8];
        en_9 = temp[9];
        en_a = temp[10];
        en_b = temp[11];
        en_c = temp[12];
        en_d = temp[13];
        en_e = temp[14];
        en_f = temp[15];

        case (sour_reg)
            4'h0: sr = reg_0;
            4'h1: sr = reg_1;
            4'h2: sr = reg_2;
            4'h3: sr = reg_3;
            4'h4: sr = reg_4;
            4'h5: sr = reg_5;
            4'h6: sr = reg_6;
            4'h7: sr = reg_7;
            4'h8: sr = reg_8;
            4'h9: sr = reg_9;
            4'hA: sr = reg_a;
            4'hB: sr = reg_b;
            4'hC: sr = reg_c;
            4'hD: sr = reg_d;
            4'hE: sr = reg_e;
            4'hF: sr = reg_f;
            default: begin
                // TODO: Original VHDL lacked explicit others for selector decode.
            end
        endcase

        case (reg_sel)
            4'h0: reg_out = reg_0;
            4'h1: reg_out = reg_1;
            4'h2: reg_out = reg_2;
            4'h3: reg_out = reg_3;
            4'h4: reg_out = reg_4;
            4'h5: reg_out = reg_5;
            4'h6: reg_out = reg_6;
            4'h7: reg_out = reg_7;
            4'h8: reg_out = reg_8;
            4'h9: reg_out = reg_9;
            4'hA: reg_out = reg_a;
            4'hB: reg_out = reg_b;
            4'hC: reg_out = reg_c;
            4'hD: reg_out = reg_d;
            4'hE: reg_out = reg_e;
            4'hF: reg_out = reg_f;
            default: reg_out = 16'h0000;
        endcase
    end
endmodule
