module cpu_uvm_top;
    import uvm_pkg::*;
    import cpu_uvm_pkg::*;

    logic clk;
    cpu_core_if cpu_if(clk);

    cpu_top dut (
        .reset(cpu_if.reset),
        .clk(clk),
        .wr(cpu_if.wr),
        .c(cpu_if.c),
        .z(cpu_if.z),
        .v(cpu_if.v),
        .s(cpu_if.s),
        .sel(cpu_if.sel),
        .reg_sel(cpu_if.reg_sel),
        .data_bus(cpu_if.data_bus),
        .address_bus(cpu_if.address_bus),
        .reg_data(cpu_if.reg_data)
    );

    assign cpu_if.exec_stage = dut.u_core.execution_stage;
    assign cpu_if.dbg_pc     = dut.u_core.pc_bus;
    assign cpu_if.dbg_ir     = dut.u_core.instruction;

    initial begin
        clk = 1'b0;
        cpu_if.init_signals();
    end

    always #5 clk = ~clk;

    initial begin
        uvm_config_db#(virtual cpu_core_if)::set(null, "*", "vif", cpu_if);
        run_test();
    end
endmodule
