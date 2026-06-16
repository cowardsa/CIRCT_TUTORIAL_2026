module transform (
    input  logic       a,
    input  logic       b,
    input  logic [7:0] x,
    output logic [7:0] out
);

always_comb begin
    case ({a, b})
        2'b00: out = x;
        2'b01: out = x + 8'd1;
        2'b10: out = -(x + 8'd1);
        2'b11: out = -x;
        default: out = '0;
    endcase
end

endmodule