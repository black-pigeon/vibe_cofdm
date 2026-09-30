`timescale 1ns/1ps
// XFFT output -> natural-bin metadata -> dual-LTF initial channel estimate.
// This is the first frequency-domain receive stage after CP removal/XFFT.
// The adapter accepts XFFT bubbles and supplies exactly one bin index per
// valid sample; the estimator consumes the first two frames only.
module cofdm_ltf_channel_chain #(
    parameter integer NFFT = 256,
    parameter integer H_FRAC_BITS = 15,
    parameter integer NV_W = 48,
    parameter [NFFT-1:0] ACTIVE_MASK = (NFFT == 256) ?
      {{{100{1'b1}}},{{55{1'b0}}},{{100{1'b1}}},1'b0} : {NFFT{1'b1}}
) (
    input wire clk, input wire rst,
    input wire fft_out_valid, output wire fft_out_ready,
    input wire fft_out_last,
    input wire signed [15:0] fft_out_re, input wire signed [15:0] fft_out_im,
    output wire channel_valid, output wire channel_last,
    output wire [7:0] channel_bin,
    output wire signed [17:0] channel_re, output wire signed [17:0] channel_im,
    output wire channel_done, output wire channel_ready, output wire channel_error,
    output wire [NV_W-1:0] noise_variance,
    output wire noise_valid,
    output wire [31:0] noise_sample_count,
    input wire h_rd_en, input wire [7:0] h_rd_bin,
    output wire signed [17:0] h_rd_re, output wire signed [17:0] h_rd_im,
    output wire h_valid
);
    wire stream_valid, stream_id, stream_last, stream_active;
    wire [7:0] stream_bin;
    wire signed [15:0] stream_re, stream_im;
    wire adapter_error;
    wire estimator_error;
    wire unused_stream_start, unused_estimator_ready;
    cofdm_ltf_fft_stream_adapter #(.NFFT(NFFT),.ACTIVE_MASK(ACTIVE_MASK)) u_adapter (
      .clk,.rst,.s_valid(fft_out_valid),.s_ready(fft_out_ready),
      .s_last(fft_out_last),.s_re(fft_out_re),.s_im(fft_out_im),
      .m_valid(stream_valid),.m_symbol_start(unused_stream_start),.m_symbol_id(stream_id),
      .m_last(stream_last),.m_bin_index(stream_bin),.m_bin_active(stream_active),
      .m_re(stream_re),.m_im(stream_im),.frame_error(adapter_error));
    cofdm_ltf_channel_estimator #(.NFFT(NFFT),.H_FRAC_BITS(H_FRAC_BITS),
      .NV_W(NV_W),.ACTIVE_MASK(ACTIVE_MASK)) u_estimator (
      .clk,.rst,.fft_valid(stream_valid),.fft_symbol_id(stream_id),.fft_last(stream_last),
      .fft_bin_index(stream_bin),.fft_bin_active(stream_active),.fft_re(stream_re),
      .fft_im(stream_im),.fft_ready(unused_estimator_ready),.channel_valid,
      .channel_last,.channel_bin,.channel_re,.channel_im,.channel_done,
      .channel_error(estimator_error),.h_rd_en,.h_rd_bin,.h_rd_re,.h_rd_im,.h_valid,
      .channel_ready,.noise_variance,.noise_valid,.noise_sample_count);
    assign channel_error = adapter_error | estimator_error;
endmodule
