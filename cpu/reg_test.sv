module reg_test (
    input  logic       clk,
    input  logic       reset,
    input  logic       input_0,
    input  logic       input_1,
    input  logic       input_2,
    input  logic       input_3,
    input  logic       input_4,
    input  logic       input_5,
    input  logic       input_6,
    input  logic       input_7,
    input  logic       input_8,
    input  logic       input_9,
    input  logic       input_a,
    input  logic       input_b,
    input  logic       input_c,
    input  logic       input_d,
    input  logic       input_e,
    input  logic       input_f,
    output logic [15:0] q
);
    logic [15:0] temp;

    always_comb begin
        temp = {input_f, input_e, input_d, input_c, input_b, input_a, input_9, input_8,
                input_7, input_6, input_5, input_4, input_3, input_2, input_1, input_0};
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset == 1'b1) begin
            q <= 16'h0000;
        end else begin
            q <= temp;
        end
    end
endmodule
