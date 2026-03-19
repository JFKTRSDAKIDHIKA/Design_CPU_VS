module bus_dir (
    input  logic        wr,
    inout  wire [15:0]  data_bus,
    input  logic [15:0] alu_out,
    output logic [15:0] mem_data
);
    assign data_bus = (wr == 1'b0) ? alu_out : 16'hzzzz;

    always_comb begin
        mem_data = data_bus;
    end
endmodule
