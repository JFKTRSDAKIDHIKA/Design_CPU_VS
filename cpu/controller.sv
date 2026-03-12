module controller (
    input  logic [2:0]  timer,
    input  logic [15:0] instruction,
    input  logic        c,
    input  logic        z,
    input  logic        v,
    input  logic        s,
    output logic [3:0]  dest_reg,
    output logic [3:0]  sour_reg,
    output logic [7:0]  offset,
    output logic [1:0]  sst,
    output logic [1:0]  sci,
    output logic [1:0]  rec,
    output logic [2:0]  alu_func,
    output logic [2:0]  alu_in_sel,
    output logic        en_reg,
    output logic        en_pc,
    output logic        wr
);
    logic [7:0] temp1;
    logic [7:0] temp2;
    logic [3:0] temp3;
    logic [3:0] temp4;
    logic [1:0] alu_out_sel;

    always_comb begin
        temp1 = instruction[15:8];
        temp2 = instruction[7:0];
        temp3 = instruction[7:4];
        temp4 = instruction[3:0];

        dest_reg    = 4'h0;
        sour_reg    = 4'h0;
        offset      = 8'h00;
        sst         = 2'b11;
        sci         = 2'b00;
        rec         = 2'b00;
        alu_func    = 3'b000;
        alu_in_sel  = 3'b000;
        wr          = 1'b1;
        alu_out_sel = 2'b00;

        case (timer)
            3'b100: begin
            end
            3'b000: begin
                sci         = 2'b01;
                alu_out_sel = 2'b10;
                alu_in_sel  = 3'b100;
                rec         = 2'b01;
            end
            3'b001: begin
                rec = 2'b10;
            end
            3'b011: begin
                case (temp1)
                    8'h00: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b00; alu_out_sel = 2'b01; alu_func = 3'b000; end
                    8'h01: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b00; alu_out_sel = 2'b01; alu_func = 3'b001; end
                    8'h02: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b00; alu_out_sel = 2'b01; alu_func = 3'b010; end
                    8'h03: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b00; alu_out_sel = 2'b00; alu_func = 3'b001; end
                    8'h04: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b00; alu_out_sel = 2'b01; alu_func = 3'b100; end
                    8'h05: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b00; alu_out_sel = 2'b00; alu_func = 3'b010; end
                    8'h06: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b00; alu_out_sel = 2'b01; alu_func = 3'b011; end
                    8'h07: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b11; alu_out_sel = 2'b01; alu_in_sel = 3'b001; end
                    8'h08: begin dest_reg = temp3; sour_reg = temp4; sci = 2'b01; sst = 2'b00; alu_out_sel = 2'b01; alu_in_sel = 3'b010; alu_func = 3'b001; end
                    8'h09: begin dest_reg = temp3; sour_reg = temp4; sci = 2'b01; sst = 2'b00; alu_out_sel = 2'b01; alu_in_sel = 3'b010; end
                    8'h0A: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b00; alu_out_sel = 2'b01; alu_in_sel = 3'b010; alu_func = 3'b101; end
                    8'h0B: begin dest_reg = temp3; sour_reg = temp4; sst = 2'b00; alu_out_sel = 2'b01; alu_in_sel = 3'b010; alu_func = 3'b110; end
                    8'h0C: begin dest_reg = temp3; sour_reg = temp4; sci = 2'b10; sst = 2'b00; alu_out_sel = 2'b01; end
                    8'h0D: begin dest_reg = temp3; sour_reg = temp4; sci = 2'b10; sst = 2'b00; alu_out_sel = 2'b01; alu_func = 3'b001; end
                    8'h40: begin offset = temp2; sst = 2'b11; alu_out_sel = 2'b10; alu_in_sel = 3'b011; end
                    8'h44: begin offset = temp2; sst = 2'b11; alu_out_sel = {c, 1'b0}; alu_in_sel = 3'b011; end
                    8'h45: begin offset = temp2; sst = 2'b11; alu_out_sel = {~c, 1'b0}; alu_in_sel = 3'b011; end
                    8'h46: begin offset = temp2; sst = 2'b11; alu_out_sel = {z, 1'b0}; alu_in_sel = 3'b011; end
                    8'h47: begin offset = temp2; sst = 2'b11; alu_out_sel = {~z, 1'b0}; alu_in_sel = 3'b011; end
                    8'h41: begin offset = temp2; sst = 2'b11; alu_out_sel = {s, 1'b0}; alu_in_sel = 3'b011; end
                    8'h43: begin offset = temp2; sst = 2'b11; alu_out_sel = {~s, 1'b0}; alu_in_sel = 3'b011; end
                    8'h78: begin offset = temp2; sst = 2'b01; alu_out_sel = 2'b00; end
                    8'h7A: begin offset = temp2; sst = 2'b10; alu_out_sel = 2'b00; end
                    default: begin
                        // TODO: Original VHDL used null here; invalid opcode handling was latch-prone.
                    end
                endcase
            end
            3'b101: begin
                dest_reg = temp3;
                sour_reg = temp4;
                sst      = 2'b11;
                case (temp1)
                    8'h80,
                    8'h81: begin
                        sci         = 2'b01;
                        alu_out_sel = 2'b10;
                        alu_in_sel  = 3'b100;
                        rec         = 2'b01;
                    end
                    8'h82: begin
                        alu_out_sel = 2'b00;
                        alu_in_sel  = 3'b001;
                        rec         = 2'b11;
                    end
                    8'h83: begin
                        alu_out_sel = 2'b00;
                        alu_in_sel  = 3'b010;
                        rec         = 2'b11;
                    end
                    default: begin
                        // TODO: Original VHDL used null here; invalid opcode handling was latch-prone.
                    end
                endcase
            end
            3'b111: begin
                dest_reg = temp3;
                sour_reg = temp4;
                case (temp1)
                    8'h82,
                    8'h81: begin
                        alu_out_sel = 2'b01;
                        alu_in_sel  = 3'b101;
                    end
                    8'h80: begin
                        alu_out_sel = 2'b10;
                        alu_in_sel  = 3'b101;
                    end
                    8'h83: begin
                        alu_out_sel = 2'b00;
                        alu_in_sel  = 3'b001;
                        wr          = 1'b0;
                    end
                    default: begin
                        // TODO: Original VHDL used null here; invalid opcode handling was latch-prone.
                    end
                endcase
            end
            default: begin
                // TODO: Original VHDL used null on timer others branch.
            end
        endcase

        en_reg = alu_out_sel[0];
        en_pc  = alu_out_sel[1];
    end
endmodule
