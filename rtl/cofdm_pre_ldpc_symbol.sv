`timescale 1ns/1ps
// Frequency-domain symbol buffer and pre-LDPC receive stage.
//
// The block intentionally separates the 256-bin XFFT stream from the
// one-symbol phase/LLR work:
//   XFFT bins -> BRAM -> 8 pilot correlation -> CORDIC atan2
//   -> common-phase LUT rotation -> matched-filter LLR stream.
// H is loaded once from cofdm_ltf_channel_chain and reused for every data or
// header symbol.  The output is still in natural carrier order; deinterleave,
// header descramble and QC-LDPC remain downstream blocks.
module cofdm_pre_ldpc_symbol #(
    parameter integer NFFT=256,
    parameter integer YW=16,
    parameter integer HW=18,
    parameter integer LLR_W=16,
    parameter integer INV_W=24,
    parameter integer ACC_W=48,
    parameter integer PHASE_W=32,
    parameter integer LLR_SHIFT=37
) (
    input wire clk, input wire rst,
    input wire h_load_valid, input wire h_load_last,
    input wire [7:0] h_load_bin,
    input wire signed [HW-1:0] h_load_re, input wire signed [HW-1:0] h_load_im,
    output wire h_load_ready,
    input wire fft_valid, input wire fft_last, input wire [7:0] fft_bin,
    input wire signed [YW-1:0] fft_re, input wire signed [YW-1:0] fft_im,
    input wire fft_pilot_sign, input wire symbol_mode_bpsk,
    input wire [INV_W-1:0] inv_noise_q16,
    output wire fft_ready,
    output reg llr_valid, output reg llr_last, output reg [7:0] llr_bin,
    output reg signed [LLR_W-1:0] llr_re, output reg signed [LLR_W-1:0] llr_im,
    output reg llr_saturated,
    output reg phase_valid, output reg signed [PHASE_W-1:0] phase,
    output reg symbol_done, output wire busy
);
  localparam integer BIN_W=8;
  localparam [2:0] S_IDLE=3'd0, S_STORE=3'd1, S_PILOT=3'd2,
                   S_REPLAY=3'd3, S_DRAIN=3'd4;
  reg [2:0] state;
  reg have_h;
  reg [7:0] pilot_bin, replay_bin;
  reg mode_q;
  reg signed [HW-1:0] h_re_mem[0:NFFT-1];
  reg signed [HW-1:0] h_im_mem[0:NFFT-1];
  reg signed [YW-1:0] y_re_mem[0:NFFT-1];
  reg signed [YW-1:0] y_im_mem[0:NFFT-1];
  reg pilot_sign_mem[0:NFFT-1];

  function automatic is_pilot(input [7:0] b);
    begin case(b)
      8'd13,8'd39,8'd65,8'd91,8'd165,8'd191,8'd217,8'd243: is_pilot=1'b1;
      default: is_pilot=1'b0;
    endcase end
  endfunction
  function automatic is_data(input [7:0] b);
    begin
      // active = bins 1..100 and 156..255, with eight pilot bins removed
      is_data=((b>=1 && b<=100)||(b>=156)) && !is_pilot(b);
    end
  endfunction
  function automatic is_last_data(input [7:0] b);
    begin is_last_data=(b==255); end
  endfunction

  wire pilot_ready;
  wire pilot_valid = (state==S_PILOT) && is_pilot(pilot_bin) && pilot_ready;
  wire pilot_last = pilot_valid && (pilot_bin==8'd243);
  wire phase_in_valid;
  wire signed [ACC_W-1:0] phase_sum_re,phase_sum_im;
  wire phase_from_cordic_valid;
  wire signed [PHASE_W-1:0] phase_from_cordic;
  wire phase_busy;
  wire [7:0] pilot_count_unused;
  cofdm_pilot_phase_accum #(.YW(YW),.HW(HW),.ACC_W(ACC_W),.PHASE_W(PHASE_W)) u_pilot (
    .clk,.rst,.pilot_valid,.pilot_last,
    .pilot_sign(pilot_sign_mem[pilot_bin]),
    .y_re(y_re_mem[pilot_bin]),.y_im(y_im_mem[pilot_bin]),
    .h_re(h_re_mem[pilot_bin]),.h_im(h_im_mem[pilot_bin]),.pilot_ready,
    .phase_in_valid,.phase_sum_re,.phase_sum_im,
    .phase_valid(phase_from_cordic_valid),.phase(phase_from_cordic),.phase_busy,
    .pilot_count(pilot_count_unused));

  reg signed [YW-1:0] rot_y_re_q,rot_y_im_q;
  reg signed [HW-1:0] rot_h_re_q,rot_h_im_q;
  reg [7:0] rot_bin_q,bin_capture_q,bin_capture_q1,bin_capture_q2,bin_capture_q3;
  reg rot_last_q,mode_replay_q;
  wire rot_in_valid=(state==S_REPLAY) && is_data(replay_bin);
  wire rot_out_valid;
  wire signed [YW-1:0] rot_y_re,rot_y_im;
  cofdm_common_phase_rotator #(.IW(YW),.OW(YW)) u_rot (
    .clk,.rst,.in_valid(rot_in_valid),.phase(phase),
    .in_re(y_re_mem[replay_bin]),.in_im(y_im_mem[replay_bin]),
    .out_valid(rot_out_valid),.out_re(rot_y_re),.out_im(rot_y_im));
  // h_*_q1 is two register stages behind the replay address, matching the
  // rotator's registered output.  No divider is used in this stage.
  reg signed [HW-1:0] h_re_q0,h_im_q0,h_re_q1,h_im_q1,h_re_q2,h_im_q2;
  reg [7:0] bin_q0,bin_q1,bin_q2;
  reg last_q0,last_q1,last_q2;
  wire llr_int_valid,llr_int_last,llr_int_sat;
  wire signed [LLR_W-1:0] llr_int_re,llr_int_im;
  wire llr_ready_unused;
  cofdm_matched_llr #(.YW(YW),.HW(HW),.LLR_W(LLR_W),.INV_W(INV_W),.LLR_SHIFT(LLR_SHIFT)) u_llr (
    .clk,.rst,.in_valid(rot_out_valid),.mode_bpsk(mode_replay_q),
    .y_re(rot_y_re),.y_im(rot_y_im),.h_re(h_re_q2),.h_im(h_im_q2),
    .inv_noise_q16,.in_ready(llr_ready_unused),.out_valid(llr_int_valid),.out_last(llr_int_last),
    .llr_re(llr_int_re),.llr_im(llr_int_im),.saturated(llr_int_sat));

  assign h_load_ready=1'b1;
  assign fft_ready=have_h && (state==S_IDLE || state==S_STORE);
  assign busy=(state!=S_IDLE) || !have_h;

  always @(posedge clk) begin
    if(rst) begin
      state<=S_IDLE; have_h<=1'b0; pilot_bin<=0; replay_bin<=0; mode_q<=0;
      phase<='0; phase_valid<=0; symbol_done<=0;
      llr_valid<=0; llr_last<=0; llr_bin<=0; llr_re<='0; llr_im<='0; llr_saturated<=0;
      rot_y_re_q<='0; rot_y_im_q<='0; rot_h_re_q<='0; rot_h_im_q<='0; rot_bin_q<=0; bin_capture_q<=0;
      rot_last_q<=0; mode_replay_q<=0; h_re_q0<='0; h_im_q0<='0; h_re_q1<='0; h_im_q1<='0; h_re_q2<='0; h_im_q2<='0;
      bin_capture_q<=0; bin_capture_q1<=0; bin_capture_q2<=0; bin_capture_q3<=0;
      bin_q0<=0; bin_q1<=0; bin_q2<=0; last_q0<=0; last_q1<=0; last_q2<=0;
    end else begin
      phase_valid<=1'b0; symbol_done<=1'b0; llr_valid<=1'b0; llr_last<=1'b0; llr_saturated<=1'b0;
      if(h_load_valid && h_load_ready) begin
        h_re_mem[h_load_bin]<=h_load_re; h_im_mem[h_load_bin]<=h_load_im;
        if(h_load_last) have_h<=1'b1;
      end
      // Pilot correlation is deliberately one carrier per cycle.  This is
      // 256 cycles of BRAM time-multiplexing rather than eight multipliers.
      if(state==S_PILOT) begin
        if(pilot_bin!=8'd255) pilot_bin<=pilot_bin+1'b1;
        if(phase_from_cordic_valid) begin
          phase<=phase_from_cordic; phase_valid<=1'b1; replay_bin<=0; mode_replay_q<=mode_q; state<=S_REPLAY;
        end
      end
      if(state==S_IDLE && have_h && fft_valid && fft_bin==0) begin
        mode_q<=symbol_mode_bpsk; state<=S_STORE;
        y_re_mem[fft_bin]<=fft_re; y_im_mem[fft_bin]<=fft_im; pilot_sign_mem[fft_bin]<=fft_pilot_sign;
        if(fft_last) begin pilot_bin<=0; state<=S_PILOT; end
      end else if(state==S_STORE && fft_valid) begin
        y_re_mem[fft_bin]<=fft_re; y_im_mem[fft_bin]<=fft_im; pilot_sign_mem[fft_bin]<=fft_pilot_sign;
        if(fft_last) begin pilot_bin<=0; state<=S_PILOT; end
      end
      // Address and H pipeline for the two-cycle LUT rotator.
      if(rot_in_valid) begin
        h_re_q0<=h_re_mem[replay_bin]; h_im_q0<=h_im_mem[replay_bin];
        bin_q0<=replay_bin; last_q0<=is_last_data(replay_bin);
      end
      h_re_q1<=h_re_q0; h_im_q1<=h_im_q0; h_re_q2<=h_re_q1; h_im_q2<=h_im_q1;
      bin_q1<=bin_q0; bin_q2<=bin_q1; last_q1<=last_q0; last_q2<=last_q1;
      if(rot_out_valid) begin
        bin_capture_q<=bin_q2;
      end
      bin_capture_q1<=bin_capture_q; bin_capture_q2<=bin_capture_q1; bin_capture_q3<=bin_capture_q2;
      if(llr_int_valid) begin
        llr_valid<=1'b1; llr_bin<=bin_capture_q3; llr_re<=llr_int_re; llr_im<=llr_int_im;
        llr_saturated<=llr_int_sat; llr_last<=(bin_capture_q3==8'd255);
      end
      if(state==S_REPLAY) begin
        if(replay_bin==8'd255) state<=S_DRAIN;
        else replay_bin<=replay_bin+1'b1;
      end
      // After the final data-bin pipeline has drained, the next symbol may
      // be accepted.  A fresh frame starts in IDLE; no unbounded buffering.
      if(state==S_DRAIN) begin
        if(llr_int_valid && bin_capture_q3==8'd255) begin symbol_done<=1'b1; state<=S_IDLE; end
      end
    end
  end
endmodule
