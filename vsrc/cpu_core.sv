module cpu_core (
    input  logic        reset,
    input  logic        clk,
    output logic        wr,
    output logic        c,
    output logic        z,
    output logic        v,
    output logic        s,
    input  logic [1:0]  sel,
    input  logic [3:0]  reg_sel,
    inout  wire [15:0] data_bus,
    output logic [15:0] address_bus,
    output logic [15:0] reg_data
);
    // cpu_core 是整个软核的数据通路顶层：
    //   - controller 根据当前执行阶段 + IR 生成控制信号
    //   - ALU / PC / reg_file / flag_reg 在这些控制信号驱动下更新体系结构状态
    //   - address_bus / data_bus 与外部 memory model 交互
    //   - reg_out 把内部状态复用成调试口 reg_data，供 testbench / debugger 观察

    localparam logic [1:0] ADDRESS_FROM_PC  = 2'b01;
    localparam logic [1:0] ADDRESS_FROM_ALU = 2'b11;

    // 这一组是 ALU 当拍算出的 flags；是否真正写入体系结构 flag_reg，
    // 由 controller 通过 sst 决定。
    logic alu_carry_flag;
    logic alu_zero_flag;
    logic alu_overflow_flag;
    logic alu_sign_flag;

    // 这一组是 flag_reg 当前保持的“体系结构可见”标志位。
    logic carry_flag;
    logic zero_flag;
    logic overflow_flag;
    logic sign_flag;

    // controller 生成的关键写使能/选择信号。
    logic pc_write_enable;
    logic reg_write_enable;
    logic alu_cin;
    logic memory_write_enable;
    logic [1:0] sst;
    logic [1:0] carry_in_select;
    logic [1:0] address_write_select;
    logic [2:0] execution_stage;
    logic [3:0] alu_func;
    logic [2:0] alu_in_sel;
    logic [3:0] d_reg;
    logic [3:0] s_reg;
    logic [7:0] offset_8;

    // instruction 是 IR 锁存后的当前指令；
    // mem_data 则是当前 data_bus 上读到的“原始外部数据”。
    // 取指阶段 mem_data 会成为 instruction，
    // 双字/访存阶段 mem_data 也可能作为立即数/内存字参与执行。
    logic [15:0] instruction;
    logic [15:0] alu_operand_a;
    logic [15:0] alu_operand_b;
    logic [15:0] alu_out;

    // reg_test 是一个调试辅助寄存器，用来把关键控制信号打包出来，
    // 便于旧 testbench / 波形快速观察控制器行为。
    logic [15:0] reg_test;

    // offset_16 是 offset_8 的符号扩展结果。
    // 对 JR / CALLA 这类相对控制流，ALU 实际看到的是它。
    logic [15:0] offset_16;

    // pc_bus / mem_data / sr / dr 是数据通路里最关键的 5 条“值通道”：
    //   pc_bus  : 当前 PC
    //   mem_data: 外部 memory 在 data_bus 上返回的字
    //   sr/dr   : reg_file 两个读端口数据
    //   alu_out : 本拍组合计算结果，可被写回寄存器、PC 或送到 data_bus
    logic [15:0] pc_bus;
    logic [15:0] mem_data;
    logic [15:0] reg_inout;
    logic [15:0] sr;
    logic [15:0] dr;
    logic        instruction_load_enable;

    // controller 只“懂指令语义”，不直接存数据。
    // 它读取 execution_stage / instruction / flags，
    // 然后告诉数据通路这一拍该怎么走：
    //   - 读哪个寄存器
    //   - ALU 做什么运算
    //   - 结果写回寄存器还是 PC
    //   - 是读内存还是写内存
    controller u_controller (
        .execution_stage(execution_stage),
        .instruction(instruction),
        .c(carry_flag),
        .z(zero_flag),
        .v(overflow_flag),
        .s(sign_flag),
        .dest_reg(d_reg),
        .sour_reg(s_reg),
        .offset(offset_8),
        .sst(sst),
        .carry_in_select(carry_in_select),
        .address_write_select(address_write_select),
        .instruction_load_enable(instruction_load_enable),
        .alu_func(alu_func),
        .alu_in_sel(alu_in_sel),
        .reg_write_enable(reg_write_enable),
        .pc_write_enable(pc_write_enable),
        .wr(memory_write_enable)
    );

    // 顶层对外导出的 wr/c/z/v/s 只是内部状态的直接别名。
    assign wr = memory_write_enable;
    assign c  = carry_flag;
    assign z  = zero_flag;
    assign v  = overflow_flag;
    assign s  = sign_flag;

    // ALU 是完全组合逻辑：
    //   controller 给出 alu_in_sel / alu_func / cin
    //   数据通路把 PC / offset / SR / DR / mem_data 喂给它
    //   它当拍产出 alu_out + 新 flags
    //
    // 特别注意：
    //   - JR / CALLA 等控制流，本质上也是借 ALU 做“PC + offset”
    //   - RET 则复用 ALU_IN_SR 这条路径完成 “PC <- R15”
    alu u_alu (
        .cin(alu_cin),
        .alu_in_sel(alu_in_sel),
        .memory_data(mem_data),
        .pc_value(pc_bus),
        .offset_value(offset_16),
        .source_reg_value(sr),
        .dest_reg_value(dr),
        .alu_func(alu_func),
        .operand_a(alu_operand_a),
        .operand_b(alu_operand_b),
        .alu_out(alu_out),
        .c(alu_carry_flag),
        .z(alu_zero_flag),
        .v(alu_overflow_flag),
        .s(alu_sign_flag)
    );

    // flag_reg 负责把 ALU 组合算出的 flags 变成时序状态。
    // sst 可以选择：
    //   - 全部保持
    //   - 按 ALU 结果更新
    //   - 单独清 C
    //   - 单独置 C
    flag_reg u_flag_reg (
        .sst(sst),
        .next_carry_flag(alu_carry_flag),
        .next_zero_flag(alu_zero_flag),
        .next_overflow_flag(alu_overflow_flag),
        .next_sign_flag(alu_sign_flag),
        .clk(clk),
        .reset(reset),
        .carry_flag(carry_flag),
        .zero_flag(zero_flag),
        .overflow_flag(overflow_flag),
        .sign_flag(sign_flag)
    );

    // execution_stage_fsm 只根据“当前内存读到的 opcode”推进阶段。
    // 它决定这一拍属于取指、单字执行、双字第二拍，还是 CALLA 的专用后两拍。
    execution_stage_fsm u_execution_stage_fsm (
        .clk(clk),
        .reset(reset),
        .inst(mem_data),
        .stage_code(execution_stage)
    );

    // 纯调试辅助寄存器，把若干控制信号打一包，挂在 reg_out 的可观察通道里。
    reg_testa u_trace_reg (
        .clk(clk),
        .reset(reset),
        .input_a(execution_stage),
        .input_b(alu_func),
        .input_c(alu_in_sel),
        .cin(alu_cin),
        .address_write_select(address_write_select),
        .instruction_load_enable(instruction_load_enable),
        .pc_en(pc_write_enable),
        .reg_en(reg_write_enable),
        .q(reg_test)
    );

    // instruction_reg 是真正的 IR。
    // 只有在 STAGE_FETCH_DECODE 且 controller 拉高 instruction_load_enable 时，
    // 才会把 data_bus 上当前取到的字锁存为“当前指令”。
    instruction_reg u_instruction_reg (
        .memory_data(mem_data),
        .load_enable(instruction_load_enable),
        .clk(clk),
        .reset_n(reset),
        .instruction(instruction)
    );

    // t1 / t2 都是很薄的组合辅助模块：
    //   t1: 根据 carry_in_select 决定 ALU cin 取 0 / 1 / 当前 C
    //   t2: 把 8 位 offset 做符号扩展，供相对控制流使用
    t1 u_carry_in_mux (
        .flag_c(carry_flag),
        .carry_in_select(carry_in_select),
        .alu_cin(alu_cin)
    );

    t2 u_offset_ext (
        .offset_8(offset_8),
        .offset_16(offset_16)
    );

    // data_bus 是三态共享总线：
    //   - wr == 1: CPU 读内存，memory_model 驱动总线，CPU 采样为 mem_data
    //   - wr == 0: CPU 写内存，CPU 驱动 alu_out 到总线，memory_model 在时钟沿写入
    //
    // 这里约定“写内存时送上总线的值”总是 alu_out。
    // 对 STRR 这类指令，controller 会让 ALU 直接旁路出源寄存器值。
    assign data_bus = (memory_write_enable == 1'b0) ? alu_out : 16'hzzzz;
    assign mem_data = data_bus;

    // address_bus 是一个时序寄存器，而不是纯组合输出。
    // 这样做的效果是：controller 在某拍决定“地址来自 PC 还是 ALU”，
    // 下一时钟沿把对应地址发到外部 memory。
    //
    // 常见几种情况：
    //   - 取指 / 取双字第二字：address_bus <- PC
    //   - LDRR / STRR：address_bus <- ALU 算出的有效地址
    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            address_bus <= 16'h0000;
        end else begin
            case (address_write_select)
                ADDRESS_FROM_PC:  address_bus <= pc_bus;
                ADDRESS_FROM_ALU: address_bus <= alu_out;
                default: begin
                end
            endcase
        end
    end

    // PC 模块本身也只是一个“可写寄存器”：
    // 只要 controller 拉高 pc_write_enable，就在时钟沿把 alu_out 装进 PC。
    //
    // 因此 PC 的所有更新语义都统一为：
    //   controller 决定 ALU 这一拍该算出什么，
    //   然后用 pc_write_enable 选择是否提交。
    //
    // 例如：
    //   - 普通取指拍：PC <- PC + 1
    //   - MVRD / JMPA 取第二字拍：PC 再 +1
    //   - JR / CALLA 最后一拍：PC <- branch target
    //   - RET：PC <- R15
    pc u_pc (
        .alu_out(alu_out),
        .en(pc_write_enable),
        .clk(clk),
        .reset(reset),
        .q(pc_bus)
    );

    // reg_out 是统一的“调试观察多路复用器”。
    // testbench / debugger 通过 sel + reg_sel 可以读取：
    //   - 通用寄存器
    //   - PC / IR
    //   - offset
    //   - ALU 输入输出
    //   - 打包后的控制痕迹 reg_test
    reg_out u_debug_mux (
        .ir(instruction),
        .pc(pc_bus),
        .reg_in(reg_inout),
        .offset(offset_16),
        .alu_a(alu_operand_a),
        .alu_b(alu_operand_b),
        .alu_out(alu_out),
        .reg_testa(reg_test),
        .reg_sel(reg_sel),
        .sel(sel),
        .reg_data(reg_data)
    );

    // reg_file 提供两读一写：
    //   - dest_sel/source_sel 对应 controller 选出的 DR/SR 编号
    //   - write_sel/write_en/write_data 决定是否把 alu_out 写回某个寄存器
    //
    // 这里沿用了原设计里“dest_data/dr”这个命名：
    //   dr 不是“写回值”，而是当前目标寄存器号对应的读出值，
    //   这样像 ADD / INC / ADDI / CALLA 这类指令都能把 DR 当作 ALU 输入之一。
    reg_file u_reg_file (
        .clk(clk),
        .reset(reset),
        .write_en(reg_write_enable),
        .write_sel(d_reg),
        .dest_sel(d_reg),
        .source_sel(s_reg),
        .debug_sel(reg_sel),
        .write_data(alu_out),
        .dest_data(dr),
        .source_data(sr),
        .debug_data(reg_inout)
    );
endmodule
