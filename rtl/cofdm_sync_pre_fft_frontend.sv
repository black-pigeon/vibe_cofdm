`timescale 1ns/1ps
// Unified time-domain receive front end before frequency-domain processing.
//
// ADC/IQ -> STF candidate and coarse CFO -> streaming NCO -> LTF search ->
// BRAM replay of LTF1/LTF2/data symbols -> XFFT input stream.
//
// The replay buffer is required because the low-resource TDM LTF matcher
// reports its result after the live samples have passed the two training
// symbols.  Connect fft_in_* directly to cofdm_fft_stream_frontend.in_*;
// fft_symbol_start marks each symbol's first CP sample.
module cofdm_sync_pre_fft_frontend #(
    parameter integer IW = 16,
    parameter integer NFFT = 256,
    parameter integer CP_LEN = 32,
    parameter integer CANDIDATES = 17,
    parameter integer SEARCH_RADIUS = 8,
    parameter integer STF_TO_LTF_USEFUL = 192,
    parameter [15:0] SCORE_MIN = 16'h1eb8,
    parameter integer TRAINING_SYMBOLS = 2,
    parameter integer DATA_SYMBOLS = 1,
    parameter integer BUFFER_DEPTH = 8192,
    parameter integer PEAK_TO_BUFFER_OFFSET = 0
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
    output wire                         fft_in_valid,
    input wire                         fft_in_ready,
    output wire signed [IW-1:0]        fft_in_re,
    output wire signed [IW-1:0]        fft_in_im,
    output wire                         fft_symbol_start,
    output wire [7:0]                   fft_symbol_index,
    output wire [1:0]                   fft_symbol_kind,
    output wire                         replay_busy,
    output wire                         replay_done,
    output wire                         replay_error,
    output wire [31:0]                  replay_start_index,
    output wire                         corrected_valid,
    output wire signed [IW-1:0]         corrected_re,
    output wire signed [IW-1:0]         corrected_im,
    output wire                         stf_candidate,
    output wire [31:0]                  stf_index,
    output wire                         coarse_valid,
    output wire signed [31:0]           coarse_phase_inc,
    output wire signed [31:0]           phase_inc,
    output wire                         coarse_locked,
    output wire                         fine_locked,
    output wire                         ltf_peak_valid,
    output wire [15:0]                  ltf_peak_score,
    output wire [31:0]                  ltf_peak_index,
    output wire                         frame_start,
    output wire                         frame_valid,
    output wire                         capture_locked,
    output wire                         capture_timeout,
    output wire [31:0]                  false_alarm_count,
    output wire [2:0]                   capture_state
);
    initial begin
      if (DATA_SYMBOLS < 1) $error("cofdm_sync_pre_fft_frontend requires DATA_SYMBOLS >= 1");
    end
    wire ltf_search_busy, ltf_search_pending, ltf_search_error;
    wire signed [47:0] ltf_corr_re, ltf_corr_im;
    wire [47:0] ltf_energy;
    wire metric_valid, clear_phase, aligned_stf_candidate;
    wire [31:0] aligned_stf_index;
    wire [31:0] frame_start_index_unused, ltf_start_index_unused;
    wire [39:0] stf_energy_old, stf_energy_new;
    wire signed [31:0] stf_angle_turns;
    wire cfo_angle_busy;
    wire candidate_valid, coarse_cfo_enable, ltf_start_evt, fine_cfo_enable, header_enable;
    wire replay_mem_error;

    cofdm_sync_ltf_cfo_top #(
      .IW(IW),.CANDIDATES(CANDIDATES),.SEARCH_RADIUS(SEARCH_RADIUS),
      .STF_TO_LTF_USEFUL(STF_TO_LTF_USEFUL),.SCORE_MIN(SCORE_MIN),
      .NFFT(NFFT),.CP_LEN(CP_LEN),.ENABLE_FINE_CHAIN(0),
      .CAP_LTF_TO_FRAME_OFFSET(2*(NFFT+CP_LEN))
    ) u_sync (
      .clk,.rst,.sample_valid,.sample_re,.sample_im,
      .fine_valid,.fine_phase_inc,.header_crc_valid,.header_crc_ok,
      .frame_abort,.frame_done,
      .fft_out_valid(1'b0),.fft_out_last(1'b0),.fft_out_re(16'sd0),
      .fft_out_im(16'sd0),.fft_rot_re(16'sd0),.fft_rot_im(16'sd0),
      .metric_valid,.stf_candidate,.stf_index,.coarse_valid,
      .coarse_phase_inc,.phase_inc,.clear_phase,.coarse_locked,.fine_locked,
      .corrected_valid,.corrected_re,.corrected_im,.phase_dbg(),
      .aligned_stf_candidate,.aligned_stf_index,.ltf_peak_valid,
      .ltf_peak_score,.ltf_peak_index,.ltf_peak_corr_re(ltf_corr_re),
      .ltf_peak_corr_im(ltf_corr_im),.ltf_peak_energy(ltf_energy),
      .ltf_search_busy,.ltf_search_pending,.ltf_search_error,
      .frame_start,.frame_valid,.capture_locked,.capture_timeout,
      .false_alarm_count,.frame_start_index(frame_start_index_unused),
      .ltf_start_index(ltf_start_index_unused),.capture_state,
      .candidate_valid,.coarse_cfo_enable,.ltf_start(ltf_start_evt),
      .fine_cfo_enable,.header_enable,.stf_angle_turns(stf_angle_turns),
      .stf_energy_old,.stf_energy_new,.cfo_angle_busy,.fft_out_ready(),
      .fine_chain_phase_valid(),.fine_chain_phase_inc(),.fine_chain_phase(),
      .fine_chain_ltf1_stored(),.fine_chain_frame_error());

    cofdm_pre_fft_replay #(
      .IW(IW),.NFFT(NFFT),.CP_LEN(CP_LEN),
      .TRAINING_SYMBOLS(TRAINING_SYMBOLS),.DATA_SYMBOLS(DATA_SYMBOLS),
      .BUFFER_DEPTH(BUFFER_DEPTH),.PEAK_TO_BUFFER_OFFSET(PEAK_TO_BUFFER_OFFSET)
    ) u_replay (
      .clk,.rst,.sample_valid(corrected_valid),.sample_re(corrected_re),
      .sample_im(corrected_im),.peak_valid(ltf_peak_valid),
      .peak_index(ltf_peak_index),.out_valid(fft_in_valid),
      .out_ready(fft_in_ready),.out_re(fft_in_re),.out_im(fft_in_im),
      .out_symbol_start(fft_symbol_start),.out_symbol_index(fft_symbol_index),
      .out_symbol_kind(fft_symbol_kind),.replay_busy,.replay_done,
      .replay_error(replay_mem_error),.replay_start_index);
    assign replay_error = ltf_search_error | replay_mem_error;
endmodule
