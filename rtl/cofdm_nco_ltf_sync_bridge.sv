`timescale 1ns/1ps
// Coarse-CFO corrected stream into the LTF synchronizer.
//
// The NCO has a fixed two-clock valid latency (sample_d_valid -> prod_valid
// -> out_valid).  STF candidate events and their accepted-sample indices are
// delayed by the same number of clocks before entering the LTF scheduler.
// Keeping this alignment in one module prevents an otherwise subtle error in
// which the LTF search window is displaced whenever the NCO is enabled.
module cofdm_nco_ltf_sync_bridge #(
    parameter integer ABSOLUTE_INDEX=0,
    parameter integer IW = 16,
    parameter integer CANDIDATES = 17,
    parameter integer SEARCH_RADIUS = 8,
    parameter integer STF_TO_LTF_USEFUL = 192,
    parameter [15:0] SCORE_MIN = 16'h1eb8,
    parameter integer NCO_EVENT_DELAY = 2
) (
    input wire                         clk,
    input wire                         rst,
    input wire                         sample_valid,
    input wire signed [IW-1:0]         sample_re,
    input wire signed [IW-1:0]         sample_im,
    input wire signed [31:0]            phase_inc,
    input wire                         clear_phase,
    input wire                         stf_hit,
    input wire [31:0]                  stf_index,
    output wire                         corrected_valid,
    output wire signed [IW-1:0]        corrected_re,
    output wire signed [IW-1:0]        corrected_im,
    output wire [31:0]                  corrected_phase,
    output wire                         aligned_stf_hit,
    output wire [31:0]                  aligned_stf_index,
    output wire                         ltf_peak_valid,
    output wire [15:0]                  ltf_peak_score,
    output wire [31:0]                  ltf_peak_index,
    output wire signed [47:0]            ltf_peak_corr_re,
    output wire signed [47:0]            ltf_peak_corr_im,
    output wire [47:0]                  ltf_peak_energy,
    output wire                         ltf_search_busy,
    output wire                         ltf_search_pending,
    output wire                         ltf_search_error
);
    cofdm_cfo_nco_rotator #(.IW(IW)) u_nco (
      .clk(clk), .rst(rst), .clear_phase(clear_phase), .sample_valid(sample_valid),
      .phase_inc(phase_inc), .in_re(sample_re), .in_im(sample_im),
      .out_valid(corrected_valid), .out_re(corrected_re), .out_im(corrected_im),
      .phase_dbg(corrected_phase));

    reg [NCO_EVENT_DELAY:0] hit_pipe;
    reg [31:0] index_pipe [0:NCO_EVENT_DELAY];
    integer k;
    always @(posedge clk) begin
        if (rst) begin
            hit_pipe <= '0;
            for (k=0; k<=NCO_EVENT_DELAY; k=k+1) index_pipe[k] <= '0;
        end else begin
            hit_pipe[0] <= stf_hit;
            index_pipe[0] <= stf_index;
            for (k=1; k<=NCO_EVENT_DELAY; k=k+1) begin
                hit_pipe[k] <= hit_pipe[k-1];
                index_pipe[k] <= index_pipe[k-1];
            end
        end
    end
    assign aligned_stf_hit = hit_pipe[NCO_EVENT_DELAY];
    assign aligned_stf_index = index_pipe[NCO_EVENT_DELAY];

    cofdm_ltf_sync_capture_frontend #(
      .ABSOLUTE_INDEX(ABSOLUTE_INDEX), .IW(IW), .CANDIDATES(CANDIDATES), .MATCHER_TDM(1),
      .SEARCH_RADIUS(SEARCH_RADIUS), .STF_TO_LTF_USEFUL(STF_TO_LTF_USEFUL),
      .SCORE_MIN(SCORE_MIN)
    ) u_ltf (
      .clk(clk), .rst(rst), .sample_valid(corrected_valid),
      .sample_re(corrected_re), .sample_im(corrected_im),
      .stf_hit(aligned_stf_hit),
      .stf_index(aligned_stf_index),
      .ltf_peak_valid(ltf_peak_valid), .ltf_peak_score(ltf_peak_score),
      .ltf_peak_index(ltf_peak_index), .ltf_peak_corr_re(ltf_peak_corr_re),
      .ltf_peak_corr_im(ltf_peak_corr_im), .ltf_peak_energy(ltf_peak_energy),
      .ltf_search_busy(ltf_search_busy), .ltf_search_pending(ltf_search_pending),
      .ltf_search_error(ltf_search_error));
endmodule
