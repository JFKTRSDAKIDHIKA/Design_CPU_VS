module cpu_tb;
    logic        reset;
    logic        clk;
    logic        wr;
    logic        c;
    logic        z;
    logic        v;
    logic        s;
    logic [1:0]  sel;
    logic [3:0]  reg_sel;
    tri   [15:0] data_bus;
    logic [15:0] address_bus;
    logic [15:0] reg_data;

    logic [15:0] mem_drive;
    logic [15:0] mem [0:255];

    assign data_bus = (wr == 1'b1) ? mem_drive : 16'hzzzz;

    cpu_top dut (
        .reset(reset),
        .clk(clk),
        .wr(wr),
        .c(c),
        .z(z),
        .v(v),
        .s(s),
        .sel(sel),
        .reg_sel(reg_sel),
        .data_bus(data_bus),
        .address_bus(address_bus),
        .reg_data(reg_data)
    );

    always #5 clk = ~clk;

    always_comb begin
        mem_drive = mem[address_bus[7:0]];
    end

    always @(posedge clk) begin
        if (wr == 1'b0) begin
            mem[address_bus[7:0]] <= data_bus;
        end
    end

    task automatic expect_reg(input logic [3:0] idx, input logic [15:0] expected, input string name);
        begin
            reg_sel = idx;
            sel = 2'b00;
            #1;
            if (reg_data !== expected) begin
                $error("%s mismatch: expected %h got %h", name, expected, reg_data);
            end
        end
    endtask

    initial begin
        clk     = 1'b0;
        reset   = 1'b0;
        sel     = 2'b00;
        reg_sel = 4'h0;

        for (int i = 0; i < 256; i = i + 1) begin
            mem[i] = 16'h0000;
        end

        mem[16'h0000] = 16'h8100; // MVRD R0, 0x0001
        mem[16'h0001] = 16'h0001;
        mem[16'h0002] = 16'h0E00; // NOT R0
        mem[16'h0003] = 16'h0F00; // ASR R0
        mem[16'h0004] = 16'h8400; // ADDI R0, 0x0002
        mem[16'h0005] = 16'h0002;
        mem[16'h0006] = 16'h8500; // ANDI R0, 0x00FF
        mem[16'h0007] = 16'h00FF;
        mem[16'h0008] = 16'hF000; // CALLA 0x0010
        mem[16'h0009] = 16'h0010;

        mem[16'h0010] = 16'h8110; // MVRD R1, 0x0003
        mem[16'h0011] = 16'h0003;
        mem[16'h0012] = 16'h8410; // ADDI R1, 0x0004
        mem[16'h0013] = 16'h0004;

        #12;
        reset = 1'b1;

        repeat (60) @(posedge clk);

        expect_reg(4'h0, 16'h0001, "R0 after NOT/ASR/ADDI/ANDI");
        expect_reg(4'h1, 16'h0007, "R1 after CALLA target code");
        expect_reg(4'hF, 16'h000A, "R15 link register after CALLA");

        if ({c, z, v, s} !== 4'b0000) begin
            $error("Flag mismatch after ANDI: expected C=0 Z=0 V=0 S=0 got %b%b%b%b", c, z, v, s);
        end

        $display("cpu_tb ISA extension regression compiled and executed");
        $finish;
    end
endmodule
