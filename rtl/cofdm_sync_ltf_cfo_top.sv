`timescale 1ns/1ps
// Closed-loop STF -> coarse CFO -> NCO -> LTF synchronization top.
//
// The fine CFO word can be supplied externally, or generated in this module
// by cofdm_ltf_fine_cfo_chain (ENABLE_FINE_CHAIN=1) after the two LTF FFTs.
// It is applied by the same cfo_control block that installs the coarse
// estimate, so the NCO phase is cleared once per candidate and then corrected
// in place without software intervention.
module cofdm_sync_ltf_cfo_top #(
    parameter integer ABSOLUTE_INDEX=0,
    parameter integer IW = 16,
    parameter integer CANDIDATES = 17,
    parameter integer SEARCH_RADIUS = 8,
    parameter integer STF_TO_LTF_USEFUL = 192,
    parameter [15:0] SCORE_MIN = 16'h1eb8,
    parameter integer CAP_LTF_MIN_OFFSET = 64,
    parameter integer CAP_LTF_MAX_OFFSET = 384,
    parameter integer CAP_LTF_TO_FRAME_OFFSET = 192,
    parameter integer CAP_LTF_TIMEOUT = 512,
    parameter integer CAP_FINE_TIMEOUT = 128,
    parameter integer CAP_HEADER_TIMEOUT = 512,
    parameter integer CAP_HOLDOFF = 256,
    parameter integer ENABLE_FINE_CHAIN = 0,
    parameter integer NFFT = 256,
    parameter integer CP_LEN = 32,
    parameter [NFFT-1:0] ACTIVE_MASK = {NFFT{1'b1}}
) (
    input wire                         clk,
    input wire                         rst,
    input wire                         sample_valid,
    input wire signed [IW-1:0]         sample_re,
    input wire signed [IW-1:0]         sample_im,
    input wire                         fine_valid,
    input wire signed [31:0]           fine_phase_inc,
    input wire                         header_crc_valid,
    input wire                         header_crc_ok,
    input wire                         frame_abort,
    input wire                         frame_done,
    input wire                         fft_out_valid,
    input wire                         fft_out_last,
    input wire signed [15:0]           fft_out_re,
    input wire signed [15:0]           fft_out_im,
    input wire signed [15:0]           fft_rot_re,
    input wire signed [15:0]           fft_rot_im,
    output wire                         metric_valid,
    output wire                         stf_candidate,
    output wire [31:0]                  stf_index,
    output wire                         coarse_valid,
    output wire signed [31:0]           coarse_phase_inc,
    output wire signed [31:0]           phase_inc,
    output wire                         clear_phase,
    output wire                         coarse_locked,
    output wire                         fine_locked,
    output wire                         corrected_valid,
    output wire signed [IW-1:0]         corrected_re,
    output wire signed [IW-1:0]         corrected_im,
    output wire [31:0]                  phase_dbg,
    output wire                         aligned_stf_candidate,
    output wire [31:0]                  aligned_stf_index,
    output wire                         ltf_peak_valid,
    output wire [15:0]                  ltf_peak_score,
    output wire [31:0]                  ltf_peak_index,
    output wire signed [47:0]            ltf_peak_corr_re,
    output wire signed [47:0]            ltf_peak_corr_im,
    output wire [47:0]                  ltf_peak_energy,
    output wire                         ltf_search_busy,
    output wire                         ltf_search_pending,
    output wire                         ltf_search_error,
    output wire                         frame_start,
    output wire                         frame_valid,
    output wire                         capture_locked,
    output wire                         capture_timeout,
    output wire [31:0]                  false_alarm_count,
    output wire [31:0]                  frame_start_index,
    output wire [31:0]                  ltf_start_index,
    output wire [2:0]                   capture_state
    ,output wire                        candidate_valid
    ,output wire                        coarse_cfo_enable
    ,output wire                        ltf_start
    ,output wire                        fine_cfo_enable
    ,output wire                        header_enable
    ,output wire signed [31:0]          stf_angle_turns
    ,output wire [39:0]                 stf_energy_old
    ,output wire [39:0]                 stf_energy_new
    ,output wire                        cfo_angle_busy
    ,output wire                        fft_out_ready
    ,output wire                        fine_chain_phase_valid
    ,output wire signed [31:0]          fine_chain_phase_inc
    ,output wire signed [31:0]          fine_chain_phase
    ,output wire                        fine_chain_ltf1_stored
    ,output wire                        fine_chain_frame_error
);
    wire signed [39:0] corr_re, corr_im;
    wire signed [31:0] coarse_inc_int;
    wire fine_valid_int;
    wire signed [31:0] fine_inc_int;

    generate
      if (ENABLE_FINE_CHAIN != 0) begin : gen_fine_chain
        wire [31:0] fine_sum_count;
        wire fine_sum_valid_unused;
        wire signed [63:0] fine_sum_re_unused, fine_sum_im_unused;
        cofdm_ltf_fine_cfo_chain #(.NFFT(NFFT),.CP_LEN(CP_LEN),.ACTIVE_MASK(ACTIVE_MASK)) u_fine_chain (
          .clk,.rst,.fft_out_valid,.fft_out_ready,.fft_out_last,
          .fft_out_re,.fft_out_im,.rot_re(fft_rot_re),.rot_im(fft_rot_im),
          .ltf1_stored(fine_chain_ltf1_stored),.fine_sum_valid(fine_sum_valid_unused),
          .fine_sum_re(fine_sum_re_unused),.fine_sum_im(fine_sum_im_unused),
          .active_count(fine_sum_count),.phase_valid(),.phase(fine_chain_phase),
          .phase_inc_valid(fine_chain_phase_valid),.phase_inc(fine_chain_phase_inc),
          .frame_error(fine_chain_frame_error));
        assign fine_valid_int = fine_chain_phase_valid;
        assign fine_inc_int = fine_chain_phase_inc;
      end else begin : gen_external_fine
        assign fft_out_ready = 1'b0;
        assign fine_chain_phase_valid = 1'b0;
        assign fine_chain_phase_inc = '0;
        assign fine_chain_phase = '0;
        assign fine_chain_ltf1_stored = 1'b0;
        assign fine_chain_frame_error = 1'b0;
        assign fine_valid_int = fine_valid;
        assign fine_inc_int = fine_phase_inc;
      end
    endgenerate

    cofdm_stf_sync_frontend #(.IW(IW),.L(16),.W(64),.ACC_W(40)) u_stf (
      .clk,.rst,.sample_valid,.sample_re,.sample_im,.metric_valid,
      .sync_hit(stf_candidate),.sync_index(stf_index),.corr_re,.corr_im,
      .energy_old(stf_energy_old),.energy_new(stf_energy_new));
    cofdm_cfo_angle_estimator #(.CW(40),.L_LOG2(4)) u_angle (
      .clk,.rst,.start(stf_candidate),.corr_re,.corr_im,.busy(cfo_angle_busy),
      .valid(coarse_valid),.angle_turns(stf_angle_turns),.phase_inc(coarse_inc_int));
    cofdm_cfo_control u_cfo_control (
      .clk,.rst,.candidate_pulse(stf_candidate),.coarse_valid,
      .coarse_inc(coarse_inc_int),.fine_valid(fine_valid_int),.fine_inc(fine_inc_int),
      .phase_inc,.clear_phase,.coarse_locked,.fine_locked);
    assign coarse_phase_inc = coarse_inc_int;

    cofdm_nco_ltf_sync_bridge #(
      .ABSOLUTE_INDEX(ABSOLUTE_INDEX),.IW(IW),.CANDIDATES(CANDIDATES),.SEARCH_RADIUS(SEARCH_RADIUS),
      .STF_TO_LTF_USEFUL(STF_TO_LTF_USEFUL),.SCORE_MIN(SCORE_MIN)
    ) u_bridge (
      .clk,.rst,.sample_valid,.sample_re,.sample_im,.phase_inc,
      .clear_phase,.stf_hit(stf_candidate),.stf_index,
      .corrected_valid,.corrected_re,.corrected_im,.corrected_phase(phase_dbg),
      .aligned_stf_hit(aligned_stf_candidate),.aligned_stf_index(aligned_stf_index),
      .ltf_peak_valid,.ltf_peak_score,.ltf_peak_index,.ltf_peak_corr_re,
      .ltf_peak_corr_im,.ltf_peak_energy,.ltf_search_busy,.ltf_search_pending,
      .ltf_search_error);

    cofdm_capture_ctrl #(
      .LTF_MIN_OFFSET(CAP_LTF_MIN_OFFSET),
      .LTF_MAX_OFFSET(CAP_LTF_MAX_OFFSET),
      .LTF_TO_FRAME_OFFSET(CAP_LTF_TO_FRAME_OFFSET),
      .LTF_TIMEOUT(CAP_LTF_TIMEOUT),.FINE_TIMEOUT(CAP_FINE_TIMEOUT),
      .HEADER_TIMEOUT(CAP_HEADER_TIMEOUT),.HOLDOFF(CAP_HOLDOFF)
    ) u_capture (
      .clk,.rst,.sample_valid(corrected_valid),.stf_hit(aligned_stf_candidate),
      .stf_index(aligned_stf_index),.ltf_peak_valid,.ltf_peak_score,
      .ltf_peak_index,.fine_cfo_valid(fine_valid_int),
      .header_crc_valid,.header_crc_ok,.frame_abort,.frame_done,
      .candidate_valid,.coarse_cfo_enable,.ltf_start,
      .fine_cfo_enable,.header_enable,.frame_start,.frame_valid,
      .capture_locked,.capture_timeout,.false_alarm_count,
      .frame_start_index,.ltf_start_index,.state_dbg(capture_state));
endmodule
