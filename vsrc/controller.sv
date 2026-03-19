module controller (
    input  logic [2:0]  execution_stage,
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
    localparam logic [2:0] STAGE_RESET_INIT        = 3'b100;
    localparam logic [2:0] STAGE_FETCH_ADDRESS     = 3'b000;
    localparam logic [2:0] STAGE_FETCH_DECODE      = 3'b001;
    localparam logic [2:0] STAGE_EXECUTE_SINGLE    = 3'b011;
    localparam logic [2:0] STAGE_FETCH_SECOND_WORD = 3'b101;
    localparam logic [2:0] STAGE_EXECUTE_DOUBLE    = 3'b111;

    localparam logic [1:0] WRITEBACK_HOLD          = 2'b00;
    localparam logic [1:0] WRITEBACK_REG           = 2'b01;
    localparam logic [1:0] WRITEBACK_PC            = 2'b10;

    localparam logic [1:0] SST_HOLD                = 2'b11;
    localparam logic [1:0] SST_WRITE               = 2'b00;
    localparam logic [1:0] SST_CLR_C               = 2'b01;
    localparam logic [1:0] SST_SET_C               = 2'b10;

    // Selects the carry-in source for the ALU: 0, constant 1, or the current carry flag.
    localparam logic [1:0] SCI_ZERO                = 2'b00;
    localparam logic [1:0] SCI_ONE                 = 2'b01;
    localparam logic [1:0] SCI_FLAG_C              = 2'b10;

    // Controls which state element captures a new value this cycle.
    localparam logic [1:0] REC_HOLD                = 2'b00;
    localparam logic [1:0] REC_LOAD_PC             = 2'b01;
    localparam logic [1:0] REC_LOAD_IR             = 2'b10;
    localparam logic [1:0] REC_LOAD_ALU            = 2'b11;

    localparam logic [2:0] ALU_ADD                 = 3'b000;
    localparam logic [2:0] ALU_SUB                 = 3'b001;
    localparam logic [2:0] ALU_AND                 = 3'b010;
    localparam logic [2:0] ALU_OR                  = 3'b011;
    localparam logic [2:0] ALU_XOR                 = 3'b100;
    localparam logic [2:0] ALU_SHL                 = 3'b101;
    localparam logic [2:0] ALU_SHR                 = 3'b110;

    // Selects which operands are driven into the ALU datapath.
    localparam logic [2:0] ALU_IN_REGS             = 3'b000;
    localparam logic [2:0] ALU_IN_SR               = 3'b001;
    localparam logic [2:0] ALU_IN_DR               = 3'b010;
    localparam logic [2:0] ALU_IN_BR               = 3'b011;
    localparam logic [2:0] ALU_IN_PC               = 3'b100;
    localparam logic [2:0] ALU_IN_MEM              = 3'b101;

    logic [7:0] opcode;
    logic [7:0] imm8;
    logic [3:0] dest_reg_index;
    logic [3:0] source_reg_index;
    logic [1:0] writeback_select;

    task automatic use_reg_operands;
        begin
            dest_reg = dest_reg_index;
            sour_reg = source_reg_index;
        end
    endtask

    always_comb begin
        opcode  = instruction[15:8];
        imm8    = instruction[7:0];
        dest_reg_index   = instruction[7:4];
        source_reg_index = instruction[3:0];

        dest_reg         = 4'h0;
        sour_reg         = 4'h0;
        offset           = 8'h00;
        sst              = SST_HOLD;
        sci              = SCI_ZERO;
        rec              = REC_HOLD;
        alu_func         = ALU_ADD;
        alu_in_sel       = ALU_IN_REGS;
        wr               = 1'b1;
        writeback_select = WRITEBACK_HOLD;

        case (execution_stage)
            STAGE_RESET_INIT: begin
            end
            STAGE_FETCH_ADDRESS: begin
                sci              = SCI_ONE;
                writeback_select = WRITEBACK_PC;
                alu_in_sel       = ALU_IN_PC;
                rec              = REC_LOAD_PC;
            end
            STAGE_FETCH_DECODE: begin
                rec = REC_LOAD_IR;
            end
            STAGE_EXECUTE_SINGLE: begin
                case (opcode)
                    8'h00: begin use_reg_operands(); sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_ADD; end
                    8'h01: begin use_reg_operands(); sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_SUB; end
                    8'h02: begin use_reg_operands(); sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_AND; end
                    8'h03: begin use_reg_operands(); sst = SST_WRITE; writeback_select = WRITEBACK_HOLD; alu_func = ALU_SUB; end
                    8'h04: begin use_reg_operands(); sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_XOR; end
                    8'h05: begin use_reg_operands(); sst = SST_WRITE; writeback_select = WRITEBACK_HOLD; alu_func = ALU_AND; end
                    8'h06: begin use_reg_operands(); sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_OR; end
                    8'h07: begin use_reg_operands(); writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_SR; end
                    8'h08: begin use_reg_operands(); sci = SCI_ONE; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_SUB; end
                    8'h09: begin use_reg_operands(); sci = SCI_ONE; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; end
                    8'h0A: begin use_reg_operands(); sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_SHL; end
                    8'h0B: begin use_reg_operands(); sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_SHR; end
                    8'h0C: begin use_reg_operands(); sci = SCI_FLAG_C; sst = SST_WRITE; writeback_select = WRITEBACK_REG; end
                    8'h0D: begin use_reg_operands(); sci = SCI_FLAG_C; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_SUB; end
                    8'h40: begin offset = imm8; writeback_select = WRITEBACK_PC; alu_in_sel = ALU_IN_BR; end
                    8'h44: begin offset = imm8; writeback_select = c ? WRITEBACK_PC : WRITEBACK_HOLD; alu_in_sel = ALU_IN_BR; end
                    8'h45: begin offset = imm8; writeback_select = c ? WRITEBACK_HOLD : WRITEBACK_PC; alu_in_sel = ALU_IN_BR; end
                    8'h46: begin offset = imm8; writeback_select = z ? WRITEBACK_PC : WRITEBACK_HOLD; alu_in_sel = ALU_IN_BR; end
                    8'h47: begin offset = imm8; writeback_select = z ? WRITEBACK_HOLD : WRITEBACK_PC; alu_in_sel = ALU_IN_BR; end
                    8'h41: begin offset = imm8; writeback_select = s ? WRITEBACK_PC : WRITEBACK_HOLD; alu_in_sel = ALU_IN_BR; end
                    8'h43: begin offset = imm8; writeback_select = s ? WRITEBACK_HOLD : WRITEBACK_PC; alu_in_sel = ALU_IN_BR; end
                    8'h78: begin offset = imm8; sst = SST_CLR_C; end
                    8'h7A: begin offset = imm8; sst = SST_SET_C; end
                    default: begin
                    end
                endcase
            end
            STAGE_FETCH_SECOND_WORD: begin
                use_reg_operands();
                case (opcode)
                    8'h80,
                    8'h81: begin
                        sci              = SCI_ONE;
                        writeback_select = WRITEBACK_PC;
                        alu_in_sel       = ALU_IN_PC;
                        rec              = REC_LOAD_PC;
                    end
                    8'h82: begin
                        alu_in_sel = ALU_IN_SR;
                        rec        = REC_LOAD_ALU;
                    end
                    8'h83: begin
                        alu_in_sel = ALU_IN_DR;
                        rec        = REC_LOAD_ALU;
                    end
                    default: begin
                    end
                endcase
            end
            STAGE_EXECUTE_DOUBLE: begin
                use_reg_operands();
                case (opcode)
                    8'h82,
                    8'h81: begin
                        writeback_select = WRITEBACK_REG;
                        alu_in_sel       = ALU_IN_MEM;
                    end
                    8'h80: begin
                        writeback_select = WRITEBACK_PC;
                        alu_in_sel       = ALU_IN_MEM;
                    end
                    8'h83: begin
                        alu_in_sel = ALU_IN_SR;
                        wr         = 1'b0;
                    end
                    default: begin
                    end
                endcase
            end
            default: begin
            end
        endcase

        en_reg = writeback_select[0];
        en_pc  = writeback_select[1];
    end
endmodule
