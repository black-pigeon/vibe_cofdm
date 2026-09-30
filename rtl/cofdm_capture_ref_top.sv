// Capture reference top: existing STF/CFO front-end plus the staged
// acquisition controller. The LTF correlator, fine-CFO estimator and PHY
// header decoder are explicit event inputs so each can be replaced and
// verified independently without changing the controller.
module cofdm_capture_ref_top #(
    parameter integer IW=16,
    parameter integer SCORE_W=16
) (
    input wire clk, input wire rst, input wire clear_phase,
    input wire sample_valid,
    input wire signed [IW-1:0] sample_re, input wire signed [IW-1:0] sample_im,
    input wire signed [31:0] phase_inc,
    input wire ltf_peak_valid,
    input wire [SCORE_W-1:0] ltf_peak_score,
    input wire [31:0] ltf_peak_index,
    input wire fine_cfo_valid,
    input wire header_crc_valid, input wire header_crc_ok,
    input wire frame_abort, input wire frame_done,
    output wire metric_valid, output wire stf_candidate,
    output wire [31:0] stf_index,
    output wire corrected_valid,
    output wire signed [IW-1:0] corrected_re, output wire signed [IW-1:0] corrected_im,
    output wire [31:0] phase_dbg,
    output wire cfo_valid, output wire signed [31:0] cfo_angle_turns,
    output wire signed [31:0] cfo_phase_inc,
    output wire candidate_valid, output wire coarse_cfo_enable,
    output wire ltf_start, output wire fine_cfo_enable,
    output wire header_enable, output wire frame_start,
    output wire frame_valid, output wire capture_locked,
    output wire capture_timeout, output wire [31:0] false_alarm_count,
    output wire [31:0] frame_start_index, output wire [31:0] ltf_start_index,
    output wire [2:0] capture_state
);
    wire signed [39:0] corr_re, corr_im;
    wire [39:0] energy_old, energy_new;
    cofdm_stf_sync_frontend #(.IW(IW),.L(16),.W(64),.ACC_W(40)) u_stf (
      .clk,.rst,.sample_valid,.sample_re,.sample_im,
      .metric_valid,.sync_hit(stf_candidate),.sync_index(stf_index),
      .corr_re,.corr_im,.energy_old,.energy_new);
    cofdm_cfo_nco_rotator #(.IW(IW)) u_nco (
      .clk,.rst,.clear_phase,.sample_valid,.phase_inc,
      .in_re(sample_re),.in_im(sample_im),.out_valid(corrected_valid),
      .out_re(corrected_re),.out_im(corrected_im),.phase_dbg);
    cofdm_cfo_angle_estimator #(.CW(40),.L_LOG2(4)) u_angle (
      .clk,.rst,.start(stf_candidate),.corr_re,.corr_im,
      .busy(),.valid(cfo_valid),.angle_turns(cfo_angle_turns),
      .phase_inc(cfo_phase_inc));
    cofdm_capture_ctrl #(.SCORE_W(SCORE_W)) u_capture (
      .clk,.rst,.sample_valid,.stf_hit(stf_candidate),.stf_index,
      .ltf_peak_valid,.ltf_peak_score,.ltf_peak_index,
      .fine_cfo_valid,.header_crc_valid,.header_crc_ok,
      .frame_abort,.frame_done,
      .candidate_valid,.coarse_cfo_enable,.ltf_start,.fine_cfo_enable,
      .header_enable,.frame_start,.frame_valid,.capture_locked,
      .capture_timeout,.false_alarm_count,.frame_start_index,
      .ltf_start_index,.state_dbg(capture_state));
endmodule
