module cpu_pnr_top (
    input  logic        reset,
    input  logic        clk,
    output logic        wr,
    output logic        c,
    output logic        z,
    output logic        v,
    output logic        s,
    input  logic [1:0]  sel,
    input  logic [3:0]  reg_sel,
    input  logic [15:0] data_bus_in,
    output logic [15:0] data_bus_out,
    output logic [15:0] address_bus,
    output logic [15:0] reg_data
);
    cpu_pnr_core u_core (
        .reset(reset),
        .clk(clk),
        .wr(wr),
        .c(c),
        .z(z),
        .v(v),
        .s(s),
        .sel(sel),
        .reg_sel(reg_sel),
        .data_bus_in(data_bus_in),
        .data_bus_out(data_bus_out),
        .address_bus(address_bus),
        .reg_data(reg_data)
    );
endmodule
