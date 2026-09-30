`timescale 1ns/1ps
// Shared pilot correlator for one OFDM symbol.
//
// e[p] = Y[p] * conj(H[p] * pilot[p])
//      = Y[p] * conj(H[p]) * pilot[p], pilot is +/-1.
// The accumulated vector is sent to the existing iterative atan2 block.
// This block deliberately accepts only the eight pilot carriers; data bins
// can continue into a symbol BRAM while the CORDIC is busy.
module cofdm_pilot_phase_accum #(
    parameter integer YW=16,
    parameter integer HW=18,
    parameter integer ACC_W=48,
    parameter integer PHASE_W=32,
    parameter integer PILOT_COUNT=8
) (
    input wire clk, input wire rst,
    input wire pilot_valid, input wire pilot_last,
    input wire pilot_sign,
    input wire signed [YW-1:0] y_re, input wire signed [YW-1:0] y_im,
    input wire signed [HW-1:0] h_re, input wire signed [HW-1:0] h_im,
    output wire pilot_ready,
    output reg phase_in_valid,
    output reg signed [ACC_W-1:0] phase_sum_re,
    output reg signed [ACC_W-1:0] phase_sum_im,
    output wire phase_valid,
    output wire signed [PHASE_W-1:0] phase,
    output wire phase_busy,
    output reg [7:0] pilot_count
);
    localparam integer PW=YW+HW;
    localparam integer CW=PW+1;
    // Register the BRAM outputs before the four DSP products.  In the
    // integrated symbol buffer this removes the asynchronous RAM read delay
    // from the accumulator's 122.88 MHz critical path.
    reg signed [YW-1:0] y_re_q,y_im_q;
    reg signed [HW-1:0] h_re_q,h_im_q;
    reg pilot_sign_q, pilot_last_q, corr_valid_q, acc_active;
    wire signed [PW-1:0] p_yr_hr = y_re_q*h_re_q;
    wire signed [PW-1:0] p_yi_hi = y_im_q*h_im_q;
    wire signed [PW-1:0] p_yi_hr = y_im_q*h_re_q;
    wire signed [PW-1:0] p_yr_hi = y_re_q*h_im_q;
    wire signed [CW-1:0] corr_re0 = $signed({p_yr_hr[PW-1],p_yr_hr}) +
                                     $signed({p_yi_hi[PW-1],p_yi_hi});
    wire signed [CW-1:0] corr_im0 = $signed({p_yi_hr[PW-1],p_yi_hr}) -
                                     $signed({p_yr_hi[PW-1],p_yr_hi});
    wire signed [ACC_W-1:0] corr_re = {{(ACC_W-CW){corr_re0[CW-1]}},corr_re0};
    wire signed [ACC_W-1:0] corr_im = {{(ACC_W-CW){corr_im0[CW-1]}},corr_im0};
    wire signed [ACC_W-1:0] signed_re = pilot_sign_q ? -corr_re : corr_re;
    wire signed [ACC_W-1:0] signed_im = pilot_sign_q ? -corr_im : corr_im;
    wire signed [ACC_W-1:0] base_re = acc_active ? phase_sum_re : '0;
    wire signed [ACC_W-1:0] base_im = acc_active ? phase_sum_im : '0;
    wire signed [ACC_W-1:0] sum_re = base_re + signed_re;
    wire signed [ACC_W-1:0] sum_im = base_im + signed_im;
    wire atan_ready;
    assign pilot_ready = !phase_in_valid && !phase_busy;
    cofdm_cordic_atan2 #(.IN_W(ACC_W),.PHASE_W(PHASE_W)) u_atan (
      .clk,.rst,.in_valid(phase_in_valid),.in_ready(atan_ready),
      .in_re(phase_sum_re),.in_im(phase_sum_im),.out_valid(phase_valid),
      .out_phase(phase),.busy(phase_busy));
    always @(posedge clk) begin
      if (rst) begin
        phase_in_valid<=1'b0; phase_sum_re<='0; phase_sum_im<='0;
        pilot_count<=0; y_re_q<='0; y_im_q<='0; h_re_q<='0; h_im_q<='0;
        pilot_sign_q<=0; pilot_last_q<=0; corr_valid_q<=0; acc_active<=0;
      end else begin
        phase_in_valid<=1'b0;
        corr_valid_q <= pilot_valid && pilot_ready;
        if (pilot_valid && pilot_ready) begin
          y_re_q<=y_re; y_im_q<=y_im; h_re_q<=h_re; h_im_q<=h_im;
          pilot_sign_q<=pilot_sign; pilot_last_q<=pilot_last;
          pilot_count<=pilot_count+1'b1;
        end
        if (corr_valid_q) begin
          phase_sum_re<=sum_re; phase_sum_im<=sum_im;
          if (pilot_last_q) begin phase_in_valid<=1'b1; pilot_count<=0; acc_active<=1'b0; end
          else acc_active<=1'b1;
        end
        if (phase_in_valid && !atan_ready)
          phase_in_valid<=1'b1;
      end
    end
endmodule
