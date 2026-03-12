module timer (
    input  logic       clk,
    input  logic       reset,
    input  logic [15:0] ins,
    output logic [2:0] \output
);
    typedef enum logic [2:0] {
        s0,
        s1,
        s2,
        s3,
        s4,
        s5
    } state_type;

    state_type state;

    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            state <= s0;
        end else begin
            case (state)
                s0: state <= s1;
                s1: state <= s2;
                s2: begin
                    if (ins[15] == 1'b0) begin
                        state <= s3;
                    end else begin
                        state <= s4;
                    end
                end
                s3: state <= s1;
                s4: state <= s5;
                s5: state <= s1;
                default: state <= s0;
            endcase
        end
    end

    always_comb begin
        case (state)
            s0: \output = 3'b100;
            s1: \output = 3'b000;
            s2: \output = 3'b001;
            s3: \output = 3'b011;
            s4: \output = 3'b101;
            s5: \output = 3'b111;
            default: \output = 3'b100;
        endcase
    end
endmodule
