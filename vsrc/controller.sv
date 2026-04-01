module controller (
    input  logic [2:0]  execution_stage,        // 来自 execution_stage_fsm 的当前执行阶段编码
    input  logic [15:0] instruction,            // 指令寄存器(IR)锁存的16位指令
    input  logic        c,                      // 当前进位标志
    input  logic        z,                      // 当前零标志
    input  logic        v,                      // 当前溢出标志
    input  logic        s,                      // 当前符号标志
    output logic [3:0]  dest_reg,               // 寄存器堆目标寄存器编号
    output logic [3:0]  sour_reg,               // 寄存器堆源寄存器编号
    output logic [7:0]  offset,                 // 8位立即数/分支偏移字段
    output logic [1:0]  sst,                    // 标志寄存器控制(保持/写入/清C/置C)
    output logic [1:0]  carry_in_select,        // ALU进位输入来源选择
    output logic [1:0]  address_write_select,   // 地址寄存器写入来源选择
    output logic        instruction_load_enable,// 取指译码阶段IR装载使能
    output logic [3:0]  alu_func,               // ALU功能选择
    output logic [2:0]  alu_in_sel,             // ALU输入通路选择
    output logic        reg_write_enable,       // 寄存器堆写使能
    output logic        pc_write_enable,        // PC写使能
    output logic        wr                      // 存储器方向控制:1读 0写
);
    localparam logic [2:0] STAGE_RESET_INIT          = 3'b100; // 复位/初始阶段
    localparam logic [2:0] STAGE_FETCH_ADDRESS       = 3'b000; // 取指1: 地址总线输出PC并自增PC
    localparam logic [2:0] STAGE_FETCH_DECODE        = 3'b001; // 取指2: 从存储器锁存指令字
    localparam logic [2:0] STAGE_EXECUTE_SINGLE      = 3'b011; // 执行单字指令
    localparam logic [2:0] STAGE_FETCH_SECOND_WORD   = 3'b101; // 双字指令第二字取数
    localparam logic [2:0] STAGE_EXECUTE_DOUBLE      = 3'b111; // 执行双字指令
    localparam logic [2:0] STAGE_SAVE_RETURN_ADDRESS = 3'b010; // 复杂调用流程: 保存返回地址
    localparam logic [2:0] STAGE_LOAD_CALL_TARGET    = 3'b110; // 复杂调用流程: 装载目标PC

    localparam logic [1:0] WRITEBACK_HOLD            = 2'b00; // 不写回
    localparam logic [1:0] WRITEBACK_REG             = 2'b01; // ALU结果写回寄存器堆
    localparam logic [1:0] WRITEBACK_PC              = 2'b10; // ALU结果写回PC

    localparam logic [1:0] SST_HOLD                  = 2'b11; // 保持当前标志位
    localparam logic [1:0] SST_WRITE                 = 2'b00; // 由ALU结果更新全部标志位
    localparam logic [1:0] SST_CLR_C                 = 2'b01; // 强制进位标志清0
    localparam logic [1:0] SST_SET_C                 = 2'b10; // 强制进位标志置1

    localparam logic [1:0] CARRY_IN_ZERO             = 2'b00; // ALU cin=0
    localparam logic [1:0] CARRY_IN_ONE              = 2'b01; // ALU cin=1
    localparam logic [1:0] CARRY_IN_FLAG_C           = 2'b10; // ALU cin=当前C标志

    localparam logic [1:0] ADDRESS_HOLD              = 2'b00; // 保持address_bus不变
    localparam logic [1:0] ADDRESS_FROM_PC           = 2'b01; // address_bus <= PC
    localparam logic [1:0] ADDRESS_FROM_ALU          = 2'b11; // address_bus <= ALU输出

    localparam logic [3:0] ALU_ADD                   = 4'b0000; // 加法
    localparam logic [3:0] ALU_SUB                   = 4'b0001; // 减法
    localparam logic [3:0] ALU_AND                   = 4'b0010; // 按位与
    localparam logic [3:0] ALU_OR                    = 4'b0011; // 按位或
    localparam logic [3:0] ALU_XOR                   = 4'b0100; // 按位异或
    localparam logic [3:0] ALU_SHL                   = 4'b0101; // 逻辑左移
    localparam logic [3:0] ALU_SHR                   = 4'b0110; // 逻辑右移
    localparam logic [3:0] ALU_NOT                   = 4'b0111; // 按位取反
    localparam logic [3:0] ALU_ASR                   = 4'b1000; // 算术右移

    localparam logic [2:0] ALU_IN_REGS               = 3'b000; // A=SR, B=DR
    localparam logic [2:0] ALU_IN_SR                 = 3'b001; // A=SR, B=0
    localparam logic [2:0] ALU_IN_DR                 = 3'b010; // A=0, B=DR
    localparam logic [2:0] ALU_IN_BR                 = 3'b011; // A=偏移量, B=PC(分支)
    localparam logic [2:0] ALU_IN_PC                 = 3'b100; // A=0, B=PC
    localparam logic [2:0] ALU_IN_MEM                = 3'b101; // A=0, B=存储器数据
    localparam logic [2:0] ALU_IN_DR_MEM             = 3'b110; // A=存储器数据, B=DR

    localparam logic [3:0] LINK_REGISTER_INDEX       = 4'hF;   // CALL流程使用的链接寄存器号

    logic [7:0] opcode;                               // 指令高8位opcode: instruction[15:8]
    logic [7:0] imm8;                                 // 指令低8位立即数字段: instruction[7:0]
    logic [3:0] dest_reg_index;                       // 目标寄存器编号: instruction[7:4]
    logic [3:0] source_reg_index;                     // 源寄存器编号: instruction[3:0]
    logic [1:0] writeback_select;                     // 内部写回选择(用于生成reg/pc写使能)

    always_comb begin
        opcode                  = instruction[15:8]; // 解析opcode
        imm8                    = instruction[7:0];  // 解析立即数/偏移
        dest_reg_index          = instruction[7:4];  // 解析目标寄存器编号
        source_reg_index        = instruction[3:0];  // 解析源寄存器编号

        dest_reg                = 4'h0;              // 默认目标寄存器
        sour_reg                = 4'h0;              // 默认源寄存器
        offset                  = 8'h00;             // 默认偏移量为0
        sst                     = SST_HOLD;          // 默认不更新标志位
        carry_in_select         = CARRY_IN_ZERO;     // 默认ALU进位输入为0
        address_write_select    = ADDRESS_HOLD;      // 默认保持地址寄存器
        instruction_load_enable = 1'b0;              // 默认不装载IR
        alu_func                = ALU_ADD;           // 默认ALU功能
        alu_in_sel              = ALU_IN_REGS;       // 默认ALU输入选择
        wr                      = 1'b1;              // 默认存储器读模式
        writeback_select        = WRITEBACK_HOLD;    // 默认不写回寄存器/PC

        case (execution_stage)
            STAGE_RESET_INIT: begin
            end
            // 地址总线输出当前PC，同时PC自增，为下一条取指做准备。
            STAGE_FETCH_ADDRESS: begin
                carry_in_select      = CARRY_IN_ONE;
                writeback_select     = WRITEBACK_PC;
                alu_in_sel           = ALU_IN_PC;
                address_write_select = ADDRESS_FROM_PC;
            end
            // 锁存存储器返回的指令字；本CPU假设一个周期完成取指。
            STAGE_FETCH_DECODE: begin
                instruction_load_enable = 1'b1;
            end
            //单字指令
            STAGE_EXECUTE_SINGLE: begin
                case (opcode)
                    8'h00: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_ADD; end
                    8'h00: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_ADD; end
                    8'h01: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_SUB; end
                    8'h02: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_AND; end
                    8'h03: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_HOLD; alu_func = ALU_SUB; end
                    8'h04: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_XOR; end
                    8'h05: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_HOLD; alu_func = ALU_AND; end
                    8'h06: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_OR; end
                    8'h07: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_SR; end
                    8'h08: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; carry_in_select = CARRY_IN_ONE; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_SUB; end
                    8'h09: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; carry_in_select = CARRY_IN_ONE; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; end
                    8'h0A: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_SHL; end
                    8'h0B: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_SHR; end
                    8'h0C: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; carry_in_select = CARRY_IN_FLAG_C; sst = SST_WRITE; writeback_select = WRITEBACK_REG; end
                    8'h0D: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; carry_in_select = CARRY_IN_FLAG_C; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_SUB; end
                    8'h0E: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_NOT; end//添加的NOT指令
                    8'h0F: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_ASR; end//添加的ASR指令
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
            //双字指令第一阶段准备好第二个操作数/地址/目标字 添加指令opcode:8'h84,8'h85
            STAGE_FETCH_SECOND_WORD: begin
                dest_reg = dest_reg_index;
                sour_reg = source_reg_index;
                case (opcode)
                    // 对于立即数/地址在下一字的双字指令：
                    // 将PC送到地址总线取第二字，并同时PC自增。
                    8'h80,
                    8'h81,
                    8'h84,
                    8'h85,
                    8'hF0: begin
                        carry_in_select      = CARRY_IN_ONE;
                        writeback_select     = WRITEBACK_PC;
                        alu_in_sel           = ALU_IN_PC;
                        address_write_select = ADDRESS_FROM_PC;
                    end
                    // 寄存器间接访存：使用源寄存器值作为地址。
                    8'h82: begin
                        alu_in_sel           = ALU_IN_SR;
                        address_write_select = ADDRESS_FROM_ALU;
                    end
                    // 寄存器间接存储：使用目标寄存器值作为地址。
                    8'h83: begin
                        alu_in_sel           = ALU_IN_DR;
                        address_write_select = ADDRESS_FROM_ALU;
                    end
                    default: begin
                    end
                endcase
            end
            //双字指令第二阶段执行操作
            STAGE_EXECUTE_DOUBLE: begin
                dest_reg = dest_reg_index;
                sour_reg = source_reg_index;
                case (opcode)
                    // 完成访存/立即数装载：将取到的字写回寄存器。
                    8'h82,
                    8'h81: begin
                        writeback_select = WRITEBACK_REG;
                        alu_in_sel       = ALU_IN_MEM;
                    end
                    // 完成绝对跳转/调用：将取到的字写入PC。
                    8'h80: begin
                        writeback_select = WRITEBACK_PC;
                        alu_in_sel       = ALU_IN_MEM;
                    end
                    // 将源寄存器值写入上一阶段选定的存储器地址。
                    8'h83: begin
                        alu_in_sel = ALU_IN_SR;
                        wr         = 1'b0;
                    end
                    // 读改写型指令：DR <- DR + 取到的存储器/立即数字。
                    8'h84: begin
                        sst              = SST_WRITE;
                        writeback_select = WRITEBACK_REG;
                        alu_in_sel       = ALU_IN_DR_MEM;
                        alu_func         = ALU_ADD;
                    end
                    // 读改写型指令：DR <- DR & 取到的存储器/立即数字。
                    8'h85: begin
                        sst              = SST_WRITE;
                        writeback_select = WRITEBACK_REG;
                        alu_in_sel       = ALU_IN_DR_MEM;
                        alu_func         = ALU_AND;
                    end
                    default: begin
                    end
                endcase
            end
            // 在CALLA目标字取到后，保存返回地址。
            STAGE_SAVE_RETURN_ADDRESS: begin
                dest_reg          = LINK_REGISTER_INDEX;
                writeback_select  = WRITEBACK_REG;
                alu_in_sel        = ALU_IN_PC;
            end
            // 将上一周期取到的第二字装载到PC。
            STAGE_LOAD_CALL_TARGET: begin
                writeback_select = WRITEBACK_PC;
                alu_in_sel       = ALU_IN_MEM;
            end
            default: begin
            end
        endcase

        reg_write_enable = writeback_select[0];      // 译码得到寄存器堆写使能
        pc_write_enable  = writeback_select[1];      // 译码得到PC写使能
    end
endmodule
