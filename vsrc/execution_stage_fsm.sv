module execution_stage_fsm (
    input  logic        clk,
    input  logic        reset,
    input  logic [15:0] inst,
    output logic [2:0]  stage_code
);
    typedef enum logic [2:0] {
        state0, // reset/initial state before the first fetch cycle starts
        state1, // fetch stage 1: drive PC onto the address path and increment PC
        state2, // fetch stage 2: latch opcode word and decide 1-word vs 2-word instruction
        state3, // execute single-word instruction
        state4, // prepare second-word access for immediate/absolute-memory instructions
        state5  // execute two-word instruction after the second word is available
    } execution_stage_state_t;

    execution_stage_state_t current_state;

    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            current_state <= state0;
        end else begin
            case (current_state)
                state0: current_state <= state1;
                state1: current_state <= state2;
                state2: begin
                    if (inst[15] == 1'b0) begin
                        current_state <= state3;
                    end else begin
                        current_state <= state4;
                    end
                end
                state3: current_state <= state1;
                state4: current_state <= state5;
                state5: current_state <= state1;
                default: current_state <= state0;
            endcase
        end
    end

    always_comb begin
        case (current_state)
            state0: stage_code = 3'b100;
            state1: stage_code = 3'b000;
            state2: stage_code = 3'b001;
            state3: stage_code = 3'b011;
            state4: stage_code = 3'b101;
            state5: stage_code = 3'b111;
            default: stage_code = 3'b100;
        endcase
    end
endmodule
