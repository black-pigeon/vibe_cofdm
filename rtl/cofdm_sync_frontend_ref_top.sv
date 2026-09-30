// Reference top for the first receive front-end slice: STF detection and
// stream CFO rotation.  phase_inc is supplied by the future angle/CFO block.
module cofdm_sync_frontend_ref_top #(
    parameter integer IW = 16
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    clear_phase,
    input  wire                    sample_valid,
    input  wire signed [IW-1:0]    sample_re,
    input  wire signed [IW-1:0]    sample_im,
    input  wire signed [31:0]      phase_inc,
    output wire                    metric_valid,
    output wire                    sync_hit,
    output wire [31:0]             sync_index,
    output wire                    corrected_valid,
    output wire signed [IW-1:0]    corrected_re,
    output wire signed [IW-1:0]    corrected_im,
    output wire [31:0]             phase_dbg,
    output wire                    cfo_valid,
    output wire signed [31:0]      cfo_angle_turns,
    output wire signed [31:0]      cfo_phase_inc
);
    wire signed [39:0] corr_re, corr_im;
    wire [39:0] energy_old, energy_new;
    cofdm_stf_sync_frontend #(.IW(IW),.L(16),.W(64),.ACC_W(40)) u_sync (
      .clk,.rst,.sample_valid,.sample_re,.sample_im,
      .metric_valid,.sync_hit,.sync_index,.corr_re,.corr_im,
      .energy_old,.energy_new);
    cofdm_cfo_nco_rotator #(.IW(IW)) u_nco (
      .clk,.rst,.clear_phase,.sample_valid,.phase_inc,
      .in_re(sample_re),.in_im(sample_im),.out_valid(corrected_valid),
      .out_re(corrected_re),.out_im(corrected_im),.phase_dbg);
    cofdm_cfo_angle_estimator #(.CW(40),.L_LOG2(4)) u_cfo_angle (
      .clk,.rst,.start(sync_hit),.corr_re,.corr_im,
      .busy(),.valid(cfo_valid),.angle_turns(cfo_angle_turns),
      .phase_inc(cfo_phase_inc));
endmodule
