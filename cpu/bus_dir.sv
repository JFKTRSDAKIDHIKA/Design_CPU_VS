module bus_dir (
    input  logic        wr,
    inout  logic [15:0] data_bus,
    input  logic [15:0] alu_out,
    output logic [15:0] mem_data
);
    always_comb begin
        mem_data = 16'h0000;
        data_bus = 16'hzzzz;
        case (wr)
            1'b1: mem_data = data_bus;
            1'b0: data_bus = alu_out;
            default: begin
                // TODO: VHDL case had no others branch; X/Z on wr may imply ambiguous behavior.
            end
        endcase
    end
endmodule
