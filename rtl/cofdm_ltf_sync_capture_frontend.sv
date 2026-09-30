`timescale 1ns/1ps
// Candidate-to-LTF front-end.  STF hit, delayed search scheduling, and the
// LTF matched-filter result are now one streaming path.  The output event
// names match cofdm_capture_ctrl, so this block can replace the former
// external ltf_peak_* test inputs.
module cofdm_ltf_sync_capture_frontend #(
    parameter integer ABSOLUTE_INDEX=0,
    parameter integer IW=16,
    parameter integer INDEX_W=32,
    parameter integer CANDIDATES=17,
    parameter integer MATCHER_TDM=0,
    parameter integer SEARCH_RADIUS=8,
    parameter integer STF_TO_LTF_USEFUL=192,
    parameter [15:0] SCORE_MIN=16'h1eb8
) (
    input wire                         clk,
    input wire                         rst,
    input wire                         sample_valid,
    input wire signed [IW-1:0]         sample_re,
    input wire signed [IW-1:0]         sample_im,
    input wire                         stf_hit,
    input wire [INDEX_W-1:0]           stf_index,
    output wire                         ltf_peak_valid,
    output wire [15:0]                 ltf_peak_score,
    output wire [INDEX_W-1:0]          ltf_peak_index,
    output wire signed [47:0]           ltf_peak_corr_re,
    output wire signed [47:0]           ltf_peak_corr_im,
    output wire [47:0]                 ltf_peak_energy,
    output wire                         ltf_search_busy,
    output wire                         ltf_search_pending,
    output wire                         ltf_search_error
);
    wire search_start;
    wire ltf_peak_valid_raw;
    wire [INDEX_W-1:0] search_base;
    wire search_ready;
    wire scheduler_pending;
    wire matcher_error;
    wire search_done = ltf_peak_valid_raw || matcher_error;
    cofdm_ltf_search_ctrl #(.INDEX_W(INDEX_W),.STF_TO_LTF_USEFUL(STF_TO_LTF_USEFUL),
      .SEARCH_RADIUS(SEARCH_RADIUS)) u_sched (
      .clk,.rst,.sample_valid,.stf_hit,.stf_index,.search_done,.search_start,
      .search_base_index(search_base),.search_pending(scheduler_pending),
      .search_error(ltf_search_error));
    generate
      if (MATCHER_TDM != 0) begin : gen_tdm_matcher
        cofdm_ltf_time_matcher_tdm #(.ABSOLUTE_INDEX(ABSOLUTE_INDEX),.IW(IW),.CANDIDATES(CANDIDATES)) u_match (
          .clk,.rst,.sample_valid,.sample_re,.sample_im,.search_start,
          .search_base_index(search_base),.search_ready,.search_busy(ltf_search_busy),
          .peak_valid(ltf_peak_valid_raw),.peak_score(ltf_peak_score),
          .peak_index(ltf_peak_index),.peak_corr_re(ltf_peak_corr_re),
          .peak_corr_im(ltf_peak_corr_im),.peak_energy(ltf_peak_energy),.search_error(matcher_error));
      end else begin : gen_parallel_matcher
        cofdm_ltf_time_matcher #(.IW(IW),.CANDIDATES(CANDIDATES)) u_match (
          .clk,.rst,.sample_valid,.sample_re,.sample_im,.search_start,
          .search_base_index(search_base),.search_ready,.search_busy(ltf_search_busy),
          .peak_valid(ltf_peak_valid_raw),.peak_score(ltf_peak_score),
          .peak_index(ltf_peak_index),.peak_corr_re(ltf_peak_corr_re),
          .peak_corr_im(ltf_peak_corr_im),.peak_energy(ltf_peak_energy),.search_error(matcher_error));
      end
    endgenerate
    // A valid event must pass both the score threshold and framing validity.
    // Keep the raw peak score available for diagnostics.
    assign ltf_peak_valid = ltf_peak_valid_raw && (ltf_peak_score >= 16'(SCORE_MIN));
    assign ltf_search_pending = scheduler_pending || ltf_search_busy || matcher_error || !search_ready;
endmodule
