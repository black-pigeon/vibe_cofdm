`timescale 1ns/1ps
// CORDIC vectoring estimator for the STF correlation angle.
//
// Input correlation is signed fixed point.  The output phase_inc is Q0.32
// turns/sample and already contains the correction sign for a delay L=16:
// phase_inc = -angle(P)/16.  One shared iterative CORDIC uses no DSP48; it
// takes ITER cycles per accepted correlation and is intended for acquisition,
// not the one-sample data path.
module cofdm_cfo_angle_estimator #(
    parameter integer CW=40,
    parameter integer L_LOG2=4,
    parameter integer ITER=16
) (
    input wire clk, rst,
    input wire start,
    input wire signed [CW-1:0] corr_re,
    input wire signed [CW-1:0] corr_im,
    output reg busy, valid,
    output reg signed [31:0] angle_turns,
    output reg signed [31:0] phase_inc
);
    localparam integer XYW=CW+8;
    /* verilator lint_off WIDTH */
    localparam [4:0] ITER_LAST=ITER-1;
    /* verilator lint_on WIDTH */
    reg signed [XYW-1:0] x,y;
    reg signed [31:0] z;
    reg [4:0] iter;
    wire signed [31:0] atan_i = atan_const(iter);
    wire signed [XYW-1:0] x_shift = y >>> iter;
    wire signed [XYW-1:0] y_shift = x >>> iter;
    wire signed [XYW-1:0] x_next = (y >= 0) ? x + x_shift : x - x_shift;
    wire signed [XYW-1:0] y_next = (y >= 0) ? y - y_shift : y + y_shift;
    wire signed [31:0] z_next = (y >= 0) ? z + atan_i : z - atan_i;

    function automatic signed [31:0] atan_const(input [4:0] k);
        begin
            case (k)
                5'd0: atan_const=32'sd536870912;
                5'd1: atan_const=32'sd316933406;
                5'd2: atan_const=32'sd167458907;
                5'd3: atan_const=32'sd85004756;
                5'd4: atan_const=32'sd42667331;
                5'd5: atan_const=32'sd21354465;
                5'd6: atan_const=32'sd10679838;
                5'd7: atan_const=32'sd5340245;
                5'd8: atan_const=32'sd2670163;
                5'd9: atan_const=32'sd1335087;
                5'd10: atan_const=32'sd667544;
                5'd11: atan_const=32'sd333772;
                5'd12: atan_const=32'sd166886;
                5'd13: atan_const=32'sd83443;
                5'd14: atan_const=32'sd41722;
                5'd15: atan_const=32'sd20861;
                default: atan_const=0;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            busy<=0; valid<=0; iter<=0; x<=0; y<=0; z<=0;
            angle_turns<=0; phase_inc<=0;
        end else begin
            valid<=0;
            if (start && !busy) begin
                busy<=1; iter<=0;
                if (corr_re[CW-1]) begin
                    x<=-$signed({{(XYW-CW){corr_re[CW-1]}},corr_re});
                    y<=-$signed({{(XYW-CW){corr_im[CW-1]}},corr_im});
                    z<=32'sh80000000;
                end else begin
                    x<=$signed({{(XYW-CW){corr_re[CW-1]}},corr_re});
                    y<=$signed({{(XYW-CW){corr_im[CW-1]}},corr_im});
                    z<=0;
                end
            end else if (busy) begin
                x<=x_next; y<=y_next; z<=z_next;
                if (iter == ITER_LAST) begin
                    busy<=0; valid<=1;
                    angle_turns<=z_next;
                    phase_inc<=-(z_next >>> L_LOG2);
                end else iter<=iter+1'b1;
            end
        end
    end
endmodule
