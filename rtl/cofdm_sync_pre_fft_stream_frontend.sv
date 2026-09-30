`timescale 1ns/1ps
// Long-frame variant of cofdm_sync_pre_fft_frontend.  The synchronizer is
// unchanged; only the post-LTF handoff uses a bounded ring replay whose
// output duration is supplied at run time.
module cofdm_sync_pre_fft_stream_frontend #(
    parameter integer IW=16,
    parameter integer NFFT=256,
    parameter integer CP_LEN=32,
    parameter integer CANDIDATES=17,
    parameter integer SEARCH_RADIUS=8,
    parameter integer STF_TO_LTF_USEFUL=192,
    parameter [15:0] SCORE_MIN=16'h1eb8,
    parameter integer BUFFER_DEPTH=8192,
    parameter integer INDEX_W=32,
    parameter integer PEAK_TO_BUFFER_OFFSET=0,
    parameter integer SYMBOL_COUNT_W=16,
    parameter integer SYMBOL_INDEX_W=8
) (
    input wire clk,input wire rst,
    input wire sample_valid,input wire signed [IW-1:0] sample_re,sample_im,
    input wire fine_valid,input wire signed [31:0] fine_phase_inc,
    input wire header_crc_valid,input wire header_crc_ok,
    input wire frame_abort,input wire frame_done,
    input wire [SYMBOL_COUNT_W-1:0] replay_symbol_count,
    input wire replay_extend_valid,
    output wire fft_in_valid,input wire fft_in_ready,
    output wire signed [IW-1:0] fft_in_re,fft_in_im,
    output wire fft_symbol_start,output wire [SYMBOL_INDEX_W-1:0] fft_symbol_index,
    output wire replay_busy,replay_done,replay_error,
    output wire stf_candidate,output wire [31:0] stf_index,
    output wire coarse_valid,output wire signed [31:0] coarse_phase_inc,
    output wire signed [31:0] phase_inc,output wire coarse_locked, fine_locked,
    output wire ltf_peak_valid,output wire [15:0] ltf_peak_score,
    output wire [31:0] ltf_peak_index,output wire frame_start,frame_valid,
    output wire capture_locked,output wire capture_timeout,
    output wire [31:0] false_alarm_count,output wire [2:0] capture_state
);
    wire corrected_valid; wire signed [IW-1:0] corrected_re,corrected_im;
    wire [31:0] ltf_start_unused,frame_index_unused;
    wire [47:0] ltf_cr,ltf_ci; wire [47:0] ltf_energy;
    wire fft_unused_ready; wire fine_chain_phase_valid; wire signed [31:0] fine_chain_inc,fine_chain_phase;
    wire fine_chain_ltf1, fine_chain_error;
    wire ltf_busy,ltf_pending,ltf_error;
    wire candidate_valid,coarse_enable,ltf_start_evt,fine_enable,header_enable;
    wire metric_valid,clear_phase; wire [31:0] aligned_index; wire aligned_hit;
    wire signed [31:0] stf_angle; wire [39:0] eold,enew; wire angle_busy;
    cofdm_sync_ltf_cfo_top #(.IW(IW),.CANDIDATES(CANDIDATES),.SEARCH_RADIUS(SEARCH_RADIUS),
      .STF_TO_LTF_USEFUL(STF_TO_LTF_USEFUL),.SCORE_MIN(SCORE_MIN),.NFFT(NFFT),.CP_LEN(CP_LEN)) u_sync(
      .clk,.rst,.sample_valid,.sample_re,.sample_im,.fine_valid,.fine_phase_inc,
      .header_crc_valid,.header_crc_ok,.frame_abort,.frame_done,
      .fft_out_valid(1'b0),.fft_out_last(1'b0),.fft_out_re(16'sd0),.fft_out_im(16'sd0),
      .fft_rot_re(16'sd0),.fft_rot_im(16'sd0),.metric_valid,.stf_candidate,
      .stf_index,.coarse_valid,.coarse_phase_inc,.phase_inc,.clear_phase,
      .coarse_locked,.fine_locked,.corrected_valid,.corrected_re,.corrected_im,
      .phase_dbg(),.aligned_stf_candidate(aligned_hit),.aligned_stf_index(aligned_index),
      .ltf_peak_valid,.ltf_peak_score,.ltf_peak_index,.ltf_peak_corr_re(ltf_cr),
      .ltf_peak_corr_im(ltf_ci),.ltf_peak_energy(ltf_energy),.ltf_search_busy(ltf_busy),
      .ltf_search_pending(ltf_pending),.ltf_search_error(ltf_error),.frame_start,
      .frame_valid,.capture_locked,.capture_timeout,.false_alarm_count,
      .frame_start_index(frame_index_unused),.ltf_start_index(ltf_start_unused),
      .capture_state,.candidate_valid,.coarse_cfo_enable(coarse_enable),.ltf_start(ltf_start_evt),
      .fine_cfo_enable(fine_enable),.header_enable,.stf_angle_turns(stf_angle),
      .stf_energy_old(eold),.stf_energy_new(enew),.cfo_angle_busy(angle_busy),
      .fft_out_ready(fft_unused_ready),.fine_chain_phase_valid,
      .fine_chain_phase_inc(fine_chain_inc),.fine_chain_phase(fine_chain_phase),
      .fine_chain_ltf1_stored(fine_chain_ltf1),.fine_chain_frame_error(fine_chain_error));
    cofdm_pre_fft_stream_replay #(.IW(IW),.NFFT(NFFT),.CP_LEN(CP_LEN),
      .BUFFER_DEPTH(BUFFER_DEPTH),.SYMBOL_COUNT_W(SYMBOL_COUNT_W),
      .SYMBOL_INDEX_W(SYMBOL_INDEX_W)) u_replay(
      .clk,.rst,.sample_valid(corrected_valid),.sample_re(corrected_re),.sample_im(corrected_im),
      .replay_start(ltf_peak_valid),
      .replay_start_index(ltf_peak_index + INDEX_W'(PEAK_TO_BUFFER_OFFSET-CP_LEN)),
      .replay_symbol_count,.replay_extend_valid,.out_valid(fft_in_valid),.out_ready(fft_in_ready),
      .out_re(fft_in_re),.out_im(fft_in_im),.out_symbol_start(fft_symbol_start),
      .out_symbol_index(fft_symbol_index),.replay_busy,
      .replay_done,.replay_error(replay_error));
endmodule
