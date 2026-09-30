`timescale 1ns/1ps
// Iterative, resource-conscious atan2.  One sample is accepted while idle;
// ITER cycles later phase_valid pulses.  The phase format is signed Q2.30
// radians in signed Q3.29 (pi = 0x6487ED51).  The datapath keeps the accumulator width so
// that a 64-bit LTF sum does not need a divider or a floating-point block.
module cofdm_cordic_atan2 #(
    parameter integer IN_W = 64,
    parameter integer PHASE_W = 32,
    parameter integer ITER = 16
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire signed [IN_W-1:0]       in_re,
    input  wire signed [IN_W-1:0]       in_im,
    output reg                          out_valid,
    output reg signed [PHASE_W-1:0]     out_phase,
    output reg                          busy
);
    localparam integer XY_W = IN_W + 1;
    localparam integer ITER_W = (ITER < 2) ? 1 : $clog2(ITER);
    localparam [ITER_W-1:0] LAST_ITER = ITER_W'(ITER-1);
    localparam signed [PHASE_W-1:0] PI = 32'sh6487ed51;
    localparam signed [PHASE_W-1:0] NEG_PI = -32'sh6487ed51;
    assign in_ready = !busy;

    reg signed [XY_W-1:0] x_reg, y_reg;
    reg signed [PHASE_W-1:0] z_reg;
    reg [ITER_W-1:0] iter_reg;

    function automatic signed [PHASE_W-1:0] atan_const(input [ITER_W-1:0] idx);
        begin
            case (idx)
                0: atan_const = 32'sh1921fb54;
                1: atan_const = 32'sh0ed63382;
                2: atan_const = 32'sh07d6dd7e;
                3: atan_const = 32'sh03fab753;
                4: atan_const = 32'sh01ff55bc;
                5: atan_const = 32'sh00ffeaae;
                6: atan_const = 32'sh007ffd55;
                7: atan_const = 32'sh003fffab;
                8: atan_const = 32'sh001ffff5;
                9: atan_const = 32'sh000fffff;
                10: atan_const = 32'sh00080000;
                11: atan_const = 32'sh00040000;
                12: atan_const = 32'sh00020000;
                13: atan_const = 32'sh00010000;
                14: atan_const = 32'sh00008000;
                default: atan_const = 32'sh00004000;
            endcase
        end
    endfunction

    wire signed [XY_W-1:0] y_shift = y_reg >>> iter_reg;
    wire signed [XY_W-1:0] x_shift = x_reg >>> iter_reg;
    // Vectoring mode: choose the rotation from the sign of y, so that each
    // iteration drives y toward zero.  (Using z here would be rotation mode
    // and produces an almost-zero result for nonzero input angles.)
    wire signed [XY_W-1:0] x_step = y_reg >= 0 ? x_reg + y_shift : x_reg - y_shift;
    wire signed [XY_W-1:0] y_step = y_reg >= 0 ? y_reg - x_shift : y_reg + x_shift;
    wire signed [PHASE_W-1:0] z_step = y_reg >= 0 ? z_reg + atan_const(iter_reg)
                                                   : z_reg - atan_const(iter_reg);

    always @(posedge clk) begin
        if (rst) begin
            x_reg <= '0; y_reg <= '0; z_reg <= '0; iter_reg <= '0;
            busy <= 1'b0; out_valid <= 1'b0; out_phase <= '0;
        end else begin
            out_valid <= 1'b0;
            if (!busy) begin
                if (in_valid) begin
                    // Rotate the negative-x half plane by +/-pi first.  This
                    // leaves the iterative CORDIC in its +/-pi/2 convergence
                    // interval while preserving the correct quadrant.
                    if (in_re < 0) begin
                        x_reg <= -$signed({in_re[IN_W-1],in_re});
                        y_reg <= -$signed({in_im[IN_W-1],in_im});
                        z_reg <= (in_im >= 0) ? PI : NEG_PI;
                    end else begin
                        x_reg <= $signed({in_re[IN_W-1],in_re});
                        y_reg <= $signed({in_im[IN_W-1],in_im});
                        z_reg <= '0;
                    end
                    iter_reg <= '0;
                    busy <= 1'b1;
                end
            end else begin
                x_reg <= x_step;
                y_reg <= y_step;
                z_reg <= z_step;
                if (iter_reg == LAST_ITER) begin
                    out_phase <= z_step;
                    out_valid <= 1'b1;
                    busy <= 1'b0;
                end else begin
                    iter_reg <= iter_reg + 1'b1;
                end
            end
        end
    end
endmodule
