module reg_testa (
    input  logic [2:0]  input_a,
    input  logic [3:0]  input_b,
    input  logic [2:0]  input_c,
    input  logic        cin,
    input  logic [1:0]  address_write_select,
    input  logic        instruction_load_enable,
    input  logic        pc_en,
    input  logic        reg_en,
    input  logic        clk,
    input  logic        reset,
    output logic [15:0] q
);
    logic [15:0] temp;

    always_comb begin
        temp = {input_a, input_b, cin, input_c, address_write_select, instruction_load_enable, pc_en, reg_en};
    end

    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            q <= 16'h0000;
        end else begin
            q <= temp;
        end
    end
endmodule
