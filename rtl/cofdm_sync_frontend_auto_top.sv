`timescale 1ns/1ps
// STF detector + coarse CFO estimator + automatically controlled NCO.
// The fine-CFO ports are optional upstream events from the LTF chain; when
// unused they may be tied low.  This top removes the former requirement that
// software provide phase_inc externally.
module cofdm_sync_frontend_auto_top #(
    parameter integer IW = 16
) (
    input wire                         clk,
    input wire                         rst,
    input wire                         sample_valid,
    input wire signed [IW-1:0]         sample_re,
    input wire signed [IW-1:0]         sample_im,
    input wire                         fine_valid,
    input wire signed [31:0]           fine_phase_inc,
    output wire                         metric_valid,
    output wire                         sync_hit,
    output wire [31:0]                  sync_index,
    output wire                         corrected_valid,
    output wire signed [IW-1:0]         corrected_re,
    output wire signed [IW-1:0]         corrected_im,
    output wire [31:0]                  phase_dbg,
    output wire                         coarse_valid,
    output wire signed [31:0]           coarse_phase_inc,
    output wire signed [31:0]           phase_inc,
    output wire                         clear_phase,
    output wire                         coarse_locked,
    output wire                         fine_locked
);
    wire signed [39:0] corr_re, corr_im;
    wire [39:0] energy_old, energy_new;
    wire signed [31:0] angle_turns;
    wire signed [31:0] nco_inc;
    wire angle_busy;
    cofdm_stf_sync_frontend #(.IW(IW),.L(16),.W(64),.ACC_W(40)) u_stf (
      .clk,.rst,.sample_valid,.sample_re,.sample_im,.metric_valid,.sync_hit,
      .sync_index,.corr_re,.corr_im,.energy_old,.energy_new);
    cofdm_cfo_angle_estimator #(.CW(40),.L_LOG2(4)) u_angle (
      .clk,.rst,.start(sync_hit),.corr_re,.corr_im,.busy(angle_busy),.valid(coarse_valid),
      .angle_turns,.phase_inc(nco_inc));
    cofdm_cfo_control u_control (
      .clk,.rst,.candidate_pulse(sync_hit),.coarse_valid,.coarse_inc(nco_inc),
      .fine_valid,.fine_inc(fine_phase_inc),.phase_inc,.clear_phase,
      .coarse_locked,.fine_locked);
    assign coarse_phase_inc = nco_inc;
    cofdm_cfo_nco_rotator #(.IW(IW)) u_nco (
      .clk,.rst,.clear_phase,.sample_valid,.phase_inc,
      .in_re(sample_re),.in_im(sample_im),.out_valid(corrected_valid),
      .out_re(corrected_re),.out_im(corrected_im),.phase_dbg);
endmodule
