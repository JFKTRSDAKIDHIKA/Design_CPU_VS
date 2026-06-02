module execution_stage_fsm (
    input  logic        clk,
    input  logic        reset,
    input  logic [15:0] inst,
    output logic [2:0]  stage_code
);
    typedef enum logic [2:0] {
        state0, // reset/initial state before the first fetch cycle starts
        state1, // fetch stage 1: drive PC onto the address path and increment PC
        state2, // fetch stage 2: latch opcode word and choose A, B, or C execution flow
        state3, // execute single-word A-group instruction
        state4, // fetch the second word for a B-group or C-group instruction
        state5, // execute regular two-cycle B-group instruction
        state6, // C-group step 1: save the return address into the link register
        state7  // C-group step 2: load the new PC from the previously fetched second word
    } execution_stage_state_t;

    execution_stage_state_t current_state;
    logic is_complex_instruction;
    logic needs_second_word;

    always_comb begin
        // C 类目前只有 CALLA。它虽然和普通双字指令一样先取第二字，
        // 但执行阶段不是直接退休，而是要额外多走两拍：
        //   1. 把返回地址写进 R15
        //   2. 再把目标地址写进 PC
        is_complex_instruction = (inst[15:8] == 8'hF0);

        // 旧版本曾用 inst[15] 来粗分单字/双字，但现在不再成立：
        // RET = F100 也是单字指令，若只看 bit15，会被误判成需要取第二字。
        // 因此这里显式列出“真的需要额外取字”的 opcode 集合。
        needs_second_word = inst[15:8] inside {8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'hF0};
    end

    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            current_state <= state0;
        end else begin
            case (current_state)
                state0: current_state <= state1;
                state1: current_state <= state2;
                state2: begin
                    // 取指译码拍结束后，先决定“下一拍到底是单字执行还是继续取第二字”。
                    // 这一步直接决定了 RET 会走普通单拍执行，而 CALLA 会走双字路径。
                    if (needs_second_word) begin
                        current_state <= state4;
                    end else begin
                        current_state <= state3;
                    end
                end
                state3: current_state <= state1;
                state4: begin
                    // 普通双字指令在取到 extension word 后直接执行；
                    // CALLA 则要切到专门的两拍返回地址/跳转目标序列。
                    if (is_complex_instruction) begin
                        current_state <= state6;
                    end else begin
                        current_state <= state5;
                    end
                end
                state5: current_state <= state1;
                state6: current_state <= state7;
                state7: current_state <= state1;
                default: current_state <= state0;
            endcase
        end
    end

    always_comb begin
        case (current_state)
            // stage_code 是 controller/monitor/testbench 共同使用的“外部可见阶段编码”。
            // 这里保持既有编码不变，避免破坏已有 VCS/UVM/Verilator 观测逻辑。
            state0: stage_code = 3'b100;
            state1: stage_code = 3'b000;
            state2: stage_code = 3'b001;
            state3: stage_code = 3'b011;
            state4: stage_code = 3'b101;
            state5: stage_code = 3'b111;
            state6: stage_code = 3'b010;
            state7: stage_code = 3'b110;
            default: stage_code = 3'b100;
        endcase
    end
endmodule
