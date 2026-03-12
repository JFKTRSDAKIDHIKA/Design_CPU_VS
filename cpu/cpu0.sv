module cpu0 (
    input  logic        reset,
    input  logic        clk,
    output logic        wr,
    output logic        c,
    output logic        z,
    output logic        v,
    output logic        s,
    input  logic [1:0]  sel,
    input  logic [3:0]  reg_sel,
    inout  logic [15:0] data_bus,
    output logic [15:0] address_bus,
    output logic [15:0] reg_data
);
    logic fc, fz, fv, fs, flag_c, flag_z, flag_v, flag_s, en_pc, en_reg, alu_cin;
    logic en_0, en_1, en_2, en_3, en_4, en_5, en_6, en_7, en_8, en_9, en_a, en_b, en_c, en_d, en_e, en_f;
    logic wre;
    logic [1:0] sst, sci, rec;
    logic [2:0] tim, alu_func, alu_in_sel;
    logic [3:0] d_reg, s_reg;
    logic [7:0] offset_8;
    logic [15:0] instruction, alu_sr, alu_dr, alu_out, reg_test, offset_16, pc_bus;
    logic [15:0] reg_0, reg_1, reg_2, reg_3, reg_4, reg_5, reg_6, reg_7;
    logic [15:0] reg_8, reg_9, reg_a, reg_b, reg_c, reg_d, reg_e, reg_f;
    logic [15:0] reg_inout, sr, dr;

    controller f1 (
        .timer(tim),
        .instruction(instruction),
        .c(flag_c),
        .z(flag_z),
        .v(flag_v),
        .s(flag_s),
        .dest_reg(d_reg),
        .sour_reg(s_reg),
        .offset(offset_8),
        .sst(sst),
        .sci(sci),
        .rec(rec),
        .alu_func(alu_func),
        .alu_in_sel(alu_in_sel),
        .en_reg(en_reg),
        .en_pc(en_pc),
        .wr(wre)
    );

    always_comb begin
        wr = wre;
        c = flag_c;
        z = flag_z;
        v = flag_v;
        s = flag_s;
    end

    alu f2 (
        .cin(alu_cin),
        .alu_a(alu_sr),
        .alu_b(alu_dr),
        .alu_func(alu_func),
        .alu_out(alu_out),
        .c(fc),
        .z(fz),
        .v(fv),
        .s(fs)
    );

    flag_reg f3 (
        .sst(sst),
        .c(fc),
        .z(fz),
        .v(fv),
        .s(fs),
        .clk(clk),
        .reset(reset),
        .flag_c(flag_c),
        .flag_z(flag_z),
        .flag_v(flag_v),
        .flag_s(flag_s)
    );

    timer f4 (
        .clk(clk),
        .reset(reset),
        .ins(data_bus),
        .\output (tim)
    );

    reg_testa f5 (
        .clk(clk),
        .reset(reset),
        .input_a(tim),
        .input_b(alu_func),
        .input_c(alu_in_sel),
        .cin(alu_cin),
        .rec(rec),
        .pc_en(en_pc),
        .reg_en(en_reg),
        .q(reg_test)
    );

    ir f6 (
        .mem_data(data_bus),
        .rec(rec),
        .clk(clk),
        .reset(reset),
        .q(instruction)
    );

    t1 f7 (
        .flag_c(flag_c),
        .sci(sci),
        .alu_cin(alu_cin)
    );

    t2 f8 (
        .offset_8(offset_8),
        .offset_16(offset_16)
    );

    t3 f9 (
        .wr(wre),
        .alu_out(alu_out),
        .\output (data_bus)
    );

    ar f10 (
        .alu_out(alu_out),
        .pc(pc_bus),
        .rec(rec),
        .clk(clk),
        .reset(reset),
        .q(address_bus)
    );

    pc f11 (
        .alu_out(alu_out),
        .en(en_pc),
        .clk(clk),
        .reset(reset),
        .q(pc_bus)
    );

    reg_out f12 (
        .ir(instruction),
        .pc(pc_bus),
        .reg_in(reg_inout),
        .offset(offset_16),
        .alu_a(alu_sr),
        .alu_b(alu_dr),
        .alu_out(alu_out),
        .reg_testa(reg_test),
        .reg_sel(reg_sel),
        .sel(sel),
        .reg_data(reg_data)
    );

    \reg r0  (.d(alu_out), .clk(clk), .reset(reset), .en(en_0), .q(reg_0));
    \reg r1  (.d(alu_out), .clk(clk), .reset(reset), .en(en_1), .q(reg_1));
    \reg r2  (.d(alu_out), .clk(clk), .reset(reset), .en(en_2), .q(reg_2));
    \reg r3  (.d(alu_out), .clk(clk), .reset(reset), .en(en_3), .q(reg_3));
    \reg r4  (.d(alu_out), .clk(clk), .reset(reset), .en(en_4), .q(reg_4));
    \reg r5  (.d(alu_out), .clk(clk), .reset(reset), .en(en_5), .q(reg_5));
    \reg r6  (.d(alu_out), .clk(clk), .reset(reset), .en(en_6), .q(reg_6));
    \reg r7  (.d(alu_out), .clk(clk), .reset(reset), .en(en_7), .q(reg_7));
    \reg r8  (.d(alu_out), .clk(clk), .reset(reset), .en(en_8), .q(reg_8));
    \reg r9  (.d(alu_out), .clk(clk), .reset(reset), .en(en_9), .q(reg_9));
    \reg r10 (.d(alu_out), .clk(clk), .reset(reset), .en(en_a), .q(reg_a));
    \reg r11 (.d(alu_out), .clk(clk), .reset(reset), .en(en_b), .q(reg_b));
    \reg r12 (.d(alu_out), .clk(clk), .reset(reset), .en(en_c), .q(reg_c));
    \reg r13 (.d(alu_out), .clk(clk), .reset(reset), .en(en_d), .q(reg_d));
    \reg r14 (.d(alu_out), .clk(clk), .reset(reset), .en(en_e), .q(reg_e));
    \reg r15 (.d(alu_out), .clk(clk), .reset(reset), .en(en_f), .q(reg_f));

    reg_mux rm (
        .reg_0(reg_0),
        .reg_1(reg_1),
        .reg_2(reg_2),
        .reg_3(reg_3),
        .reg_4(reg_4),
        .reg_5(reg_5),
        .reg_6(reg_6),
        .reg_7(reg_7),
        .reg_8(reg_8),
        .reg_9(reg_9),
        .reg_a(reg_a),
        .reg_b(reg_b),
        .reg_c(reg_c),
        .reg_d(reg_d),
        .reg_e(reg_e),
        .reg_f(reg_f),
        .dest_reg(d_reg),
        .sour_reg(s_reg),
        .reg_sel(reg_sel),
        .en(en_reg),
        .en_0(en_0),
        .en_1(en_1),
        .en_2(en_2),
        .en_3(en_3),
        .en_4(en_4),
        .en_5(en_5),
        .en_6(en_6),
        .en_7(en_7),
        .en_8(en_8),
        .en_9(en_9),
        .en_a(en_a),
        .en_b(en_b),
        .en_c(en_c),
        .en_d(en_d),
        .en_e(en_e),
        .en_f(en_f),
        .dr(dr),
        .sr(sr),
        .reg_out(reg_inout)
    );

    bus_mux bm (
        .alu_in_sel(alu_in_sel),
        .data(data_bus),
        .pc(pc_bus),
        .offset(offset_16),
        .sr(sr),
        .dr(dr),
        .alu_sr(alu_sr),
        .alu_dr(alu_dr)
    );
endmodule
