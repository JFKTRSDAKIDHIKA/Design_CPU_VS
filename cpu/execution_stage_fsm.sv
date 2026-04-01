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

    always_comb begin
        is_complex_instruction = (inst[15:8] == 8'hF0);
    end

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
                state4: begin
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
