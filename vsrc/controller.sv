module controller (
    input  logic [2:0]  execution_stage,        // 当前微阶段，由 execution_stage_fsm 提供
    input  logic [15:0] instruction,            // IR 中锁存的当前指令字
    input  logic        c,                      // 当前体系结构 C 标志
    input  logic        z,                      // 当前体系结构 Z 标志
    input  logic        v,                      // 当前体系结构 V 标志
    input  logic        s,                      // 当前体系结构 S 标志
    output logic [3:0]  dest_reg,               // reg_file 目标寄存器编号（同时也是写回目标编号）
    output logic [3:0]  sour_reg,               // reg_file 源寄存器编号
    output logic [7:0]  offset,                 // 从 instruction[7:0] 解析出的立即数/偏移字段
    output logic [1:0]  sst,                    // flag_reg 更新模式
    output logic [1:0]  carry_in_select,        // ALU cin 来源选择
    output logic [1:0]  address_write_select,   // address_bus 下一拍装入来源
    output logic        instruction_load_enable,// IR 装载使能
    output logic [3:0]  alu_func,               // ALU 功能码
    output logic [2:0]  alu_in_sel,             // ALU 输入路由选择
    output logic        reg_write_enable,       // 通用寄存器写使能
    output logic        pc_write_enable,        // PC 写使能
    output logic        wr                      // 存储器方向：1=读，0=写
);
    // -------------------------------------------------------------------------
    // controller 是整个 CPU 数据通路的“组合式控制中心”。
    //
    // 它的输入只有三类：
    //   1. 当前处于哪个执行阶段 execution_stage
    //   2. 当前指令 instruction（来自 IR）
    //   3. 当前 flags（用于条件分支等）
    //
    // 它的输出则是数据通路执行本拍所需的全部控制信号：
    //   - 读哪个寄存器
    //   - ALU 执行哪种运算、输入取哪几路
    //   - 是否更新 flags
    //   - 是否写回寄存器/PC
    //   - address_bus 下一拍装入 PC 还是 ALU
    //   - data_bus 当前是读内存还是写内存
    //
    // 设计风格上，这里采用“先给默认值，再按阶段/指令覆写”的方式。
    // 这样做的关键好处是：
    //   - 默认状态天然安全，不会误写寄存器或 flags
    //   - 控制流指令（CALLA/RET/JR）只需显式拉起需要的那几个控制位
    //   - 新增指令时只需在对应阶段补 case 分支，副作用更可控
    // -------------------------------------------------------------------------

    // ===== 执行阶段编码 =====
    // 这些编码由 execution_stage_fsm 统一定义，并被 controller、monitor、
    // debugger、testbench 共同使用，所以这里不能随意改动。
    localparam logic [2:0] STAGE_RESET_INIT          = 3'b100; // 复位初始空拍
    localparam logic [2:0] STAGE_FETCH_ADDRESS       = 3'b000; // 取指拍1：address_bus <- PC，同时 PC <- PC+1
    localparam logic [2:0] STAGE_FETCH_DECODE        = 3'b001; // 取指拍2：IR <- mem_data
    localparam logic [2:0] STAGE_EXECUTE_SINGLE      = 3'b011; // 单字指令执行/退休拍
    localparam logic [2:0] STAGE_FETCH_SECOND_WORD   = 3'b101; // 双字/访存类指令的预备拍
    localparam logic [2:0] STAGE_EXECUTE_DOUBLE      = 3'b111; // 普通双字指令执行/退休拍
    localparam logic [2:0] STAGE_SAVE_RETURN_ADDRESS = 3'b010; // CALLA 专用拍1：R15 <- PC_after_calla
    localparam logic [2:0] STAGE_LOAD_CALL_TARGET    = 3'b110; // CALLA 专用拍2：PC <- PC_after_calla + rel8

    // ===== 内部统一写回编码 =====
    // controller 在中间逻辑里先表达“本拍结果写回到哪里”，
    // 最后再统一拆成 reg_write_enable / pc_write_enable。
    localparam logic [1:0] WRITEBACK_HOLD            = 2'b00; // 本拍结果不提交到寄存器堆或 PC
    localparam logic [1:0] WRITEBACK_REG             = 2'b01; // 本拍 ALU 结果写回通用寄存器
    localparam logic [1:0] WRITEBACK_PC              = 2'b10; // 本拍 ALU 结果写回 PC

    // ===== flags 更新模式 =====
    // sst 直接驱动 flag_reg，决定拍末 flags 如何变化。
    localparam logic [1:0] SST_HOLD                  = 2'b11; // flags 全保持
    localparam logic [1:0] SST_WRITE                 = 2'b00; // 用 ALU 本拍输出的 C/Z/V/S 全量更新
    localparam logic [1:0] SST_CLR_C                 = 2'b01; // 仅将 C 清 0
    localparam logic [1:0] SST_SET_C                 = 2'b10; // 仅将 C 置 1

    // ===== ALU cin 来源 =====
    // 通过这组编码，ADD/ADC、SUB/DEC/SBB 等运算可以共用一套 ALU 主体。
    localparam logic [1:0] CARRY_IN_ZERO             = 2'b00; // cin = 0
    localparam logic [1:0] CARRY_IN_ONE              = 2'b01; // cin = 1
    localparam logic [1:0] CARRY_IN_FLAG_C           = 2'b10; // cin = 当前体系结构 C

    // ===== address_bus 装载来源 =====
    // address_bus 是时序寄存器，因此 controller 决定的是“下一拍地址来自哪一路”。
    localparam logic [1:0] ADDRESS_HOLD              = 2'b00; // 本拍不改 address_bus
    localparam logic [1:0] ADDRESS_FROM_PC           = 2'b01; // 下一拍 address_bus <- 当前 PC
    localparam logic [1:0] ADDRESS_FROM_ALU          = 2'b11; // 下一拍 address_bus <- ALU 结果

    // ===== ALU 功能码 =====
    localparam logic [3:0] ALU_ADD                   = 4'b0000; // 加法/地址偏移相加
    localparam logic [3:0] ALU_SUB                   = 4'b0001; // 减法/比较
    localparam logic [3:0] ALU_AND                   = 4'b0010; // 按位与
    localparam logic [3:0] ALU_OR                    = 4'b0011; // 按位或
    localparam logic [3:0] ALU_XOR                   = 4'b0100; // 按位异或
    localparam logic [3:0] ALU_SHL                   = 4'b0101; // 逻辑左移
    localparam logic [3:0] ALU_SHR                   = 4'b0110; // 逻辑右移
    localparam logic [3:0] ALU_NOT                   = 4'b0111; // 按位取反
    localparam logic [3:0] ALU_ASR                   = 4'b1000; // 算术右移

    // ===== ALU 输入路由 =====
    // 这颗 ALU 不只做普通寄存器运算，也承担：
    //   - PC 自增
    //   - JR/CALLA 的 PC + signext(offset)
    //   - MVRD/LDRR 的 mem_data -> reg 写回
    //   - ADDI/ANDI 的 DR 与第二字立即数运算
    localparam logic [2:0] ALU_IN_REGS               = 3'b000; // A=SR,           B=DR
    localparam logic [2:0] ALU_IN_SR                 = 3'b001; // A=SR,           B=0
    localparam logic [2:0] ALU_IN_DR                 = 3'b010; // A=0,            B=DR
    localparam logic [2:0] ALU_IN_BR                 = 3'b011; // A=signext(off), B=PC
    localparam logic [2:0] ALU_IN_PC                 = 3'b100; // A=0,            B=PC
    localparam logic [2:0] ALU_IN_MEM                = 3'b101; // A=0,            B=mem_data
    localparam logic [2:0] ALU_IN_DR_MEM             = 3'b110; // A=mem_data,     B=DR

    // ===== 特殊寄存器/操作码约定 =====
    // 约定 R15 作为 link register：
    //   - CALLA 把返回地址写进 R15
    //   - RET 从 R15 取返回地址写回 PC
    localparam logic [3:0] LINK_REGISTER_INDEX       = 4'hF;
    localparam logic [7:0] OPCODE_CALLA              = 8'hF0;
    localparam logic [7:0] OPCODE_RET                = 8'hF1;

    // 从 instruction 中拆解出的常用字段。
    // 注意：并不是每条指令都会真正使用这些字段。
    // 例如 RET 无操作数，因此不能机械依赖 instruction[3:0]。
    logic [7:0] opcode;
    logic [7:0] imm8;
    logic [3:0] dest_reg_index;
    logic [3:0] source_reg_index;

    // controller 内部统一使用的“结果写回目标”编码。
    // bit0 -> reg_write_enable
    // bit1 -> pc_write_enable
    logic [1:0] writeback_select;

    always_comb begin
        // ===== 从 IR 拆出字段 =====
        opcode                  = instruction[15:8];
        imm8                    = instruction[7:0];
        dest_reg_index          = instruction[7:4];
        source_reg_index        = instruction[3:0];

        // ===== 安全默认值 =====
        // 默认值刻意选择为“尽量不做事”：
        //   - 不写 flags
        //   - 不写寄存器
        //   - 不写 PC
        //   - 不改 address_bus
        //   - 总线方向保持读
        // 后续 case 分支只覆写本条路径真正需要改动的少数控制位。
        dest_reg                = 4'h0;
        sour_reg                = 4'h0;
        offset                  = 8'h00;
        sst                     = SST_HOLD;
        carry_in_select         = CARRY_IN_ZERO;
        address_write_select    = ADDRESS_HOLD;
        instruction_load_enable = 1'b0;
        alu_func                = ALU_ADD;
        alu_in_sel              = ALU_IN_REGS;
        wr                      = 1'b1;
        writeback_select        = WRITEBACK_HOLD;

        // ===== 第一层分派：按执行阶段决定本拍职责 =====
        // 同一条指令在不同阶段干的事可能完全不同，所以 controller 必须先看阶段、
        // 再在对应阶段内按 opcode 细分控制行为。
        case (execution_stage)
            STAGE_RESET_INIT: begin
                // 复位初始阶段不需要主动驱动任何操作，保持默认值即可。
            end

            // -----------------------------------------------------------------
            // 取指拍1
            // 语义：
            //   address_bus <- 当前 PC
            //   PC          <- PC + 1
            //
            // 这里通过 ALU_IN_PC + cin=1 复用 ALU 完成“PC 加 1”，
            // 同时让 address_bus 下一拍指向当前 PC 对应的内存地址。
            // -----------------------------------------------------------------
            STAGE_FETCH_ADDRESS: begin
                carry_in_select      = CARRY_IN_ONE;
                writeback_select     = WRITEBACK_PC;
                alu_in_sel           = ALU_IN_PC;
                address_write_select = ADDRESS_FROM_PC;
            end

            // -----------------------------------------------------------------
            // 取指拍2
            // memory 已在 data_bus 上返回本条指令字，本拍只需把它锁进 IR。
            // -----------------------------------------------------------------
            STAGE_FETCH_DECODE: begin
                instruction_load_enable = 1'b1;
            end

            // -----------------------------------------------------------------
            // 单字指令执行拍
            //
            // 这一拍统一完成所有单字指令的退休，主要可以分成 4 大类：
            //   1. 双寄存器 ALU/比较指令：ADD/SUB/AND/CMP/...
            //   2. 单寄存器 ALU 指令：DEC/INC/SHL/SHR/NOT/ASR
            //   3. 相对分支：JR/JRC/JRZ/...
            //   4. 特殊控制：CLC/STC/RET
            //
            // 读这一段的建议思路：
            //   先看这条指令是否需要 DR/SR
            //   再看 ALU 输入模式和运算类型
            //   最后看 flags 是否更新、结果写回寄存器还是 PC
            // -----------------------------------------------------------------
            STAGE_EXECUTE_SINGLE: begin
                case (opcode)
                    // --- 双寄存器运算/比较 ---
                    8'h00: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG;  alu_func = ALU_ADD; end
                    8'h01: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG;  alu_func = ALU_SUB; end
                    8'h02: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG;  alu_func = ALU_AND; end
                    8'h03: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_HOLD; alu_func = ALU_SUB; end
                    8'h04: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG;  alu_func = ALU_XOR; end
                    8'h05: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_HOLD; alu_func = ALU_AND; end
                    8'h06: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; sst = SST_WRITE; writeback_select = WRITEBACK_REG;  alu_func = ALU_OR;  end
                    8'h07: begin dest_reg = dest_reg_index; sour_reg = source_reg_index;                      writeback_select = WRITEBACK_REG;  alu_in_sel = ALU_IN_SR; end

                    // --- 单寄存器运算 ---
                    8'h08: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; carry_in_select = CARRY_IN_ONE;    sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_SUB; end
                    8'h09: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; carry_in_select = CARRY_IN_ONE;    sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; end
                    8'h0A: begin dest_reg = dest_reg_index; sour_reg = source_reg_index;                                    sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_SHL; end
                    8'h0B: begin dest_reg = dest_reg_index; sour_reg = source_reg_index;                                    sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_SHR; end
                    8'h0C: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; carry_in_select = CARRY_IN_FLAG_C; sst = SST_WRITE; writeback_select = WRITEBACK_REG; end
                    8'h0D: begin dest_reg = dest_reg_index; sour_reg = source_reg_index; carry_in_select = CARRY_IN_FLAG_C; sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_func = ALU_SUB; end
                    8'h0E: begin dest_reg = dest_reg_index; sour_reg = source_reg_index;                                    sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_NOT; end
                    8'h0F: begin dest_reg = dest_reg_index; sour_reg = source_reg_index;                                    sst = SST_WRITE; writeback_select = WRITEBACK_REG; alu_in_sel = ALU_IN_DR; alu_func = ALU_ASR; end

                    // --- 相对分支 ---
                    // 统一复用 ALU_IN_BR 路径，使 ALU 计算：
                    //   PC + signext(imm8)
                    // 是否真正提交到 PC，则由条件判断决定。
                    8'h40: begin offset = imm8; writeback_select = WRITEBACK_PC;             alu_in_sel = ALU_IN_BR; end
                    8'h44: begin offset = imm8; writeback_select = c ? WRITEBACK_PC   : WRITEBACK_HOLD; alu_in_sel = ALU_IN_BR; end
                    8'h45: begin offset = imm8; writeback_select = c ? WRITEBACK_HOLD : WRITEBACK_PC;   alu_in_sel = ALU_IN_BR; end
                    8'h46: begin offset = imm8; writeback_select = z ? WRITEBACK_PC   : WRITEBACK_HOLD; alu_in_sel = ALU_IN_BR; end
                    8'h47: begin offset = imm8; writeback_select = z ? WRITEBACK_HOLD : WRITEBACK_PC;   alu_in_sel = ALU_IN_BR; end
                    8'h41: begin offset = imm8; writeback_select = s ? WRITEBACK_PC   : WRITEBACK_HOLD; alu_in_sel = ALU_IN_BR; end
                    8'h43: begin offset = imm8; writeback_select = s ? WRITEBACK_HOLD : WRITEBACK_PC;   alu_in_sel = ALU_IN_BR; end

                    // --- 标志控制 ---
                    8'h78: begin offset = imm8; sst = SST_CLR_C; end
                    8'h7A: begin offset = imm8; sst = SST_SET_C; end

                    // --- RET：单字返回 ---
                    // RET 没有显式操作数字段，所以不能依赖 instruction[3:0]。
                    // controller 在这里强制指定 source = R15，并复用已有路径：
                    //   alu_in_sel       = ALU_IN_SR
                    //   writeback_select = WRITEBACK_PC
                    //
                    // 数据通路最终完成：
                    //   alu_out = R15
                    //   PC     <- alu_out
                    //
                    // 同时由于 sst 与 reg 写回保持默认值，RET 满足：
                    //   - 不更新 flags
                    //   - 不写普通寄存器
                    OPCODE_RET: begin
                        sour_reg         = LINK_REGISTER_INDEX;
                        writeback_select = WRITEBACK_PC;
                        alu_in_sel       = ALU_IN_SR;
                    end

                    default: begin
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // 双字/访存预备拍
            //
            // 这一拍的职责不是退休指令，而是“把下一拍所需的数据来源准备好”。
            // 大致分两类：
            //   1. extension word 型：
            //      MVRD / JMPA / ADDI / ANDI / CALLA
            //      需要先把 PC 指向下一字，并让 PC 自增
            //   2. 寄存器间接访存型：
            //      LDRR / STRR
            //      需要先用寄存器值形成有效地址
            // -----------------------------------------------------------------
            STAGE_FETCH_SECOND_WORD: begin
                dest_reg = dest_reg_index;
                sour_reg = source_reg_index;
                case (opcode)
                    // 下一字即为立即数/地址/保留字：
                    //   address_bus <- PC
                    //   PC <- PC + 1
                    8'h80,
                    8'h81,
                    8'h84,
                    8'h85,
                    OPCODE_CALLA: begin
                        carry_in_select      = CARRY_IN_ONE;
                        writeback_select     = WRITEBACK_PC;
                        alu_in_sel           = ALU_IN_PC;
                        address_write_select = ADDRESS_FROM_PC;
                    end

                    // LDRR：有效地址来自 SR
                    8'h82: begin
                        alu_in_sel           = ALU_IN_SR;
                        address_write_select = ADDRESS_FROM_ALU;
                    end

                    // STRR：有效地址来自 DR
                    8'h83: begin
                        alu_in_sel           = ALU_IN_DR;
                        address_write_select = ADDRESS_FROM_ALU;
                    end

                    default: begin
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // 普通双字指令执行/退休拍
            //
            // 这里处理所有经过上一拍准备后、现在已经可以真正提交结果的双字指令。
            // CALLA 不走这里，是因为它需要两个顺序相关的写回动作：
            //   1. R15 <- 返回地址
            //   2. PC  <- 调用目标
            // 所以 CALLA 拆成了后面的两个专用阶段。
            // -----------------------------------------------------------------
            STAGE_EXECUTE_DOUBLE: begin
                dest_reg = dest_reg_index;
                sour_reg = source_reg_index;
                case (opcode)
                    // LDRR / MVRD：
                    // 本拍 mem_data 已经有效，直接通过 ALU_IN_MEM 写回寄存器
                    8'h82,
                    8'h81: begin
                        writeback_select = WRITEBACK_REG;
                        alu_in_sel       = ALU_IN_MEM;
                    end

                    // JMPA：
                    // 下一字就是绝对跳转目标，直接写回 PC
                    8'h80: begin
                        writeback_select = WRITEBACK_PC;
                        alu_in_sel       = ALU_IN_MEM;
                    end

                    // STRR：
                    // ALU_IN_SR 让 alu_out 直接等于 SR，CPU 在 wr=0 时驱动 data_bus 完成写内存
                    8'h83: begin
                        alu_in_sel = ALU_IN_SR;
                        wr         = 1'b0;
                    end

                    // ADDI：DR <- DR + imm16
                    8'h84: begin
                        sst              = SST_WRITE;
                        writeback_select = WRITEBACK_REG;
                        alu_in_sel       = ALU_IN_DR_MEM;
                        alu_func         = ALU_ADD;
                    end

                    // ANDI：DR <- DR & imm16
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

            // -----------------------------------------------------------------
            // CALLA 专用拍1：保存返回地址
            //
            // 在取第二字阶段执行完后，PC 已经前进到：
            //   PC_after_calla = addr_calla + 2
            // 这正是调用完成后应该返回的位置。
            //
            // 因此这一拍只需令：
            //   alu_out = 当前 PC
            //   R15    <- alu_out
            // 就能得到正确的 link address。
            // -----------------------------------------------------------------
            STAGE_SAVE_RETURN_ADDRESS: begin
                dest_reg          = LINK_REGISTER_INDEX; // R15    <- alu_out
                writeback_select  = WRITEBACK_REG; 
                alu_in_sel        = ALU_IN_PC; // alu_out = 当前 PC
            end

            // -----------------------------------------------------------------
            // CALLA 专用拍2：装载调用目标
            //
            // 目标地址使用与 JR 相同的相对公式：
            //   target = PC_after_calla + signext(rel8)
            //
            // 这样设计的好处是：
            //   - CALLA 的返回地址与跳转基址统一参考 PC_after_calla
            //   - 可复用 JR 现有的 ALU_IN_BR 数据通路
            //   - 第二字虽然目前保留不用，仍然保持双字格式的一致性
            // -----------------------------------------------------------------
            STAGE_LOAD_CALL_TARGET: begin
                offset           = imm8;
                writeback_select = WRITEBACK_PC;
                alu_in_sel       = ALU_IN_BR;
            end

            default: begin
            end
        endcase

        // ===== 统一展开写回使能 =====
        // 前面的控制分支只表达“结果写给谁”，这里再集中转换成实际使能位。
        reg_write_enable = writeback_select[0];
        pc_write_enable  = writeback_select[1];
    end
endmodule
