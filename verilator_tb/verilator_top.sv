// Simulation-friendly top wrapper around cpu_top.
// Splits the inout data_bus into dedicated mem-to-cpu and cpu-to-mem
// unidirectional ports, and brings out internal observation signals
// (PC, IR, R15, execution_stage) so the C++ testbench can check
// architectural state directly.
module verilator_top (
    input  logic        clk,
    input  logic        reset,
    input  logic [1:0]  sel,
    input  logic [3:0]  reg_sel,
    input  logic [15:0] mem_to_cpu,
    output logic [15:0] cpu_to_mem,
    output logic [15:0] address_bus,
    output logic        wr,
    output logic        c,
    output logic        z,
    output logic        v,
    output logic        s,
    output logic [15:0] reg_data,
    output logic [2:0]  execution_stage,
    output logic [15:0] pc_value,
    output logic [15:0] ir_value,
    output logic [15:0] r15_value
);
    wire [15:0] data_bus;

    // External memory drives the bus when the CPU is in read mode (wr==1).
    assign data_bus = wr ? mem_to_cpu : 16'hzzzz;
    // Capture whatever is currently on data_bus; valid CPU output appears when wr==0.
    assign cpu_to_mem = data_bus;

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

    assign execution_stage = dut.u_core.execution_stage;
    assign pc_value        = dut.u_core.pc_bus;
    assign ir_value        = dut.u_core.instruction;
    assign r15_value       = dut.u_core.u_reg_file.regs[15];
endmodule
