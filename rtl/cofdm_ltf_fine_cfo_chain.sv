`timescale 1ns/1ps
// Integrated post-XFFT LTF path:
//   AXI output stream -> bin/frame metadata -> dual-LTF accumulator
//   -> iterative atan2 -> fixed-point NCO phase increment.
// The XFFT itself remains an IP in cofdm_fft_stream_frontend; this block is
// deliberately IP-independent so it can be unit-tested with recorded XFFT
// output and then inserted after the generated core.
module cofdm_ltf_fine_cfo_chain #(
    parameter integer NFFT = 256,
    parameter integer CP_LEN = 32,
    parameter [NFFT-1:0] ACTIVE_MASK = {NFFT{1'b1}},
    parameter integer USE_ROT_ROM = 1
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         fft_out_valid,
    output wire                         fft_out_ready,
    input  wire                         fft_out_last,
    input  wire signed [15:0]           fft_out_re,
    input  wire signed [15:0]           fft_out_im,
    input  wire signed [15:0]           rot_re,
    input  wire signed [15:0]           rot_im,
    output wire                         ltf1_stored,
    output wire                         fine_sum_valid,
    output wire signed [63:0]           fine_sum_re,
    output wire signed [63:0]           fine_sum_im,
    output wire [31:0]                  active_count,
    output wire                         phase_valid,
    output wire signed [31:0]           phase,
    output wire                         phase_inc_valid,
    output wire signed [31:0]           phase_inc,
    output wire                         frame_error
);
    wire stream_valid, stream_start, stream_id, stream_last, stream_active;
    wire [7:0] stream_bin;
    wire signed [15:0] stream_re, stream_im;
    wire atan_ready, atan_busy, phase_valid_int;
    assign phase_valid = phase_valid_int && !atan_busy;

    cofdm_ltf_fft_stream_adapter #(.NFFT(NFFT), .ACTIVE_MASK(ACTIVE_MASK))
    u_adapter (
      .clk(clk), .rst(rst), .s_valid(fft_out_valid), .s_ready(fft_out_ready),
      .s_last(fft_out_last), .s_re(fft_out_re), .s_im(fft_out_im),
      .m_valid(stream_valid), .m_symbol_start(stream_start),
      .m_symbol_id(stream_id), .m_last(stream_last), .m_bin_index(stream_bin),
      .m_bin_active(stream_active), .m_re(stream_re), .m_im(stream_im),
      .frame_error(frame_error));

    cofdm_ltf_fine_cfo_accum #(.NFFT(NFFT),.USE_ROT_ROM(USE_ROT_ROM)) u_accum (
      .clk(clk), .rst(rst), .fft_valid(stream_valid),
      .fft_symbol_start(stream_start), .fft_last(stream_last),
      .fft_symbol_id(stream_id), .fft_bin_index(stream_bin),
      .fft_bin_active(stream_active), .fft_re(stream_re), .fft_im(stream_im),
      .rot_re(rot_re), .rot_im(rot_im), .ltf1_stored(ltf1_stored),
      .fine_sum_valid(fine_sum_valid), .fine_sum_re(fine_sum_re),
      .fine_sum_im(fine_sum_im), .active_count(active_count));

    cofdm_cordic_atan2 #(.IN_W(64), .PHASE_W(32), .ITER(16)) u_atan2 (
      .clk(clk), .rst(rst), .in_valid(fine_sum_valid && atan_ready), .in_ready(atan_ready),
      .in_re(fine_sum_re), .in_im(fine_sum_im), .out_valid(phase_valid_int),
      .out_phase(phase), .busy(atan_busy));

    cofdm_fine_cfo_phase_to_inc #(.NFFT(NFFT), .CP_LEN(CP_LEN)) u_phase_inc (
      .clk(clk), .rst(rst), .in_valid(phase_valid), .in_phase(phase),
      .out_valid(phase_inc_valid), .out_phase_inc(phase_inc));
endmodule
