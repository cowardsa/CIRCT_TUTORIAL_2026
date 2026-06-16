module dot_product (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [7:0] c,
    input  wire [7:0] d,
    output wire [15:0] out
);
    assign out = (a * b) + (c * d);

endmodule