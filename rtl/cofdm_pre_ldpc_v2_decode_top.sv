`timescale 1ns/1ps
// Resource-budget integration top: pre-LDPC stream plus v2 Header gate.
// Payload is exposed only after Header CRC/field validation.  The full
// time-domain replay controller remains upstream and is intentionally not
// duplicated here.
module cofdm_pre_ldpc_v2_decode_top #(parameter integer LLR_W=16)(
    input wire clk,rst,frame_start,
    input wire h_load_valid,h_load_last,input wire [7:0] h_load_bin,
    input wire signed [17:0] h_load_re,h_load_im,output wire h_load_ready,
    input wire fft_valid,fft_last,input wire [7:0] fft_bin,
    input wire signed [15:0] fft_re,fft_im,output wire fft_ready,
    input wire symbol_header,pilot_skip_midamble,input wire [23:0] inv_noise_q16,
    input wire [15:0] n_codewords,
    output wire payload_valid,payload_last,output wire signed [LLR_W-1:0] payload_llr,
    input wire payload_ready,output wire header_valid,header_ok,crc_ok,
    output wire [11:0] payload_bytes,output wire [6:0] scrambler_seed,
    output wire [1:0] midamble_code,output wire header_error,output wire busy
);
    wire stream_valid,stream_ready,stream_header,stream_last;
    wire signed [LLR_W-1:0] stream_llr;
    cofdm_pre_ldpc_stream #(.LLR_W(LLR_W)) pre(
      .clk,.rst,.frame_start,.h_load_valid,.h_load_last,.h_load_bin,.h_load_re,.h_load_im,.h_load_ready,
      .fft_valid,.fft_last,.fft_bin,.fft_re,.fft_im,.fft_ready,.symbol_header,.pilot_skip_midamble,
      .inv_noise_q16,.n_codewords,.out_valid(stream_valid),.out_ready(stream_ready),.out_llr(stream_llr),
      .out_header(stream_header),.out_symbol_last(stream_last),.out_cw_first(),.out_cw_last(),.symbol_done(),.frame_error());
    cofdm_v2_rx_header_path #(.LLR_W(LLR_W)) hdr(
      .clk,.rst,.frame_start,.stream_valid,.stream_header,.stream_last,.stream_llr,.stream_ready,
      .payload_valid,.payload_last,.payload_llr,.payload_ready,.header_valid,.header_ok,.crc_ok,
      .payload_bytes,.scrambler_seed,.midamble_code,.header_error,.busy);
endmodule
