module t2 (
    input  logic [7:0]  offset_8,
    output logic [15:0] offset_16
);
    always_comb begin
        if (offset_8[7] == 1'b1) begin
            offset_16 = {8'hFF, offset_8};
        end else begin
            offset_16 = {8'h00, offset_8};
        end
    end
endmodule
