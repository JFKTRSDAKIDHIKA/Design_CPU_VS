module reg_file (
    input  logic        clk,
    input  logic        reset,
    input  logic        write_en,
    input  logic [3:0]  write_sel,
    input  logic [3:0]  dest_sel,
    input  logic [3:0]  source_sel,
    input  logic [3:0]  debug_sel,
    input  logic [15:0] write_data,
    output logic [15:0] dest_data,
    output logic [15:0] source_data,
    output logic [15:0] debug_data
);
    logic [15:0] regs [0:15];

    always_ff @(posedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            for (int i = 0; i < 16; i = i + 1) begin
                regs[i] <= 16'h0000;
            end
        end else if (write_en == 1'b1) begin
            regs[write_sel] <= write_data;
        end
    end

    always_comb begin
        dest_data   = regs[dest_sel];
        source_data = regs[source_sel];
        debug_data  = regs[debug_sel];
    end
endmodule
