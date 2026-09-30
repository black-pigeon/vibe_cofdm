// Select the nearest of four quadrant rotations from a complex correlation.
// No CORDIC, atan2, divider or multiplier is required.
module cofdm_quadrant_select #(parameter integer W = 40) (
    input  wire signed [W-1:0] corr_re,
    input  wire signed [W-1:0] corr_im,
    output reg [1:0] rot_code
);
    wire [W-1:0] abs_re = corr_re[W-1] ? -corr_re : corr_re;
    wire [W-1:0] abs_im = corr_im[W-1] ? -corr_im : corr_im;
    always @* begin
        if (abs_re >= abs_im)
            rot_code = corr_re[W-1] ? 2'd2 : 2'd0;
        else
            rot_code = corr_im[W-1] ? 2'd3 : 2'd1;
    end
endmodule
