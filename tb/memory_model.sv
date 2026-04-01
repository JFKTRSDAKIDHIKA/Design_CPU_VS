module memory_model #(
    parameter int MEM_DEPTH = 65536
) (
    input  logic        clk,
    input  logic        wr,
    input  logic [15:0] address_bus,
    inout  tri   [15:0] data_bus
);
    logic [15:0] mem [0:MEM_DEPTH-1];

    assign data_bus = (wr == 1'b1) ? mem[address_bus] : 16'hzzzz;

    task automatic clear();
        for (int i = 0; i < MEM_DEPTH; i++) begin
            mem[i] = 16'h0000;
        end
    endtask

    task automatic load_hex(input string mem_file);
        begin
            clear();
            $display("[memory_model] loading %s", mem_file);
            $readmemh(mem_file, mem);
        end
    endtask

    always @(posedge clk) begin
        if (wr == 1'b0) begin
            mem[address_bus] <= data_bus;
        end
    end
endmodule
