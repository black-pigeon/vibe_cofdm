`timescale 1ns/1ps
// Complete receive boundary through Payload bytes.
//
// cofdm_phy_rx_v2_top remains the timing/synchronization and frequency-domain
// reference core.  This wrapper adds the bounded Payload backend after its
// already verified, deinterleaved Payload LLR stream:
//
//   Header OK -> bounded LDPC codeword buffer -> descramble/CRC/padding
//             -> byte stream
//
// The raw LLR and PHY diagnostics are intentionally retained.  They make it
// possible to compare an FPGA frame against MATLAB at either the LLR boundary
// or the final byte boundary without changing the receive core.
module cofdm_phy_rx_v2_payload_top #(
    parameter integer BUFFER_DEPTH = 8192,
    parameter integer INPUT_SHIFT = 0,
    parameter integer STF_TO_LTF_USEFUL = 144,
    parameter integer PEAK_TO_BUFFER_OFFSET = 0
) (
    input wire clk, rst, sample_valid,
    input wire signed [15:0] sample_re, sample_im,
    input wire [23:0] inv_noise_q16,
    input wire payload_byte_ready,
    output wire payload_byte_valid,
    output wire [7:0] payload_byte,
    output wire payload_byte_last,
    output wire payload_frame_done,
    output wire payload_frame_error,
    output wire payload_crc_ok, payload_padding_ok, payload_ldpc_ok,
    output wire payload_backend_busy,
    output wire [4:0] payload_decoder_iterations,
    output wire [15:0] payload_codeword_index,
    output wire payload_start_rejected,
    // Raw PHY/LLR observability.
    output wire payload_llr_valid, payload_llr_last,
    output wire payload_llr_cw_first, payload_llr_cw_last,
    output wire signed [15:0] payload_llr,
    output wire header_valid, header_ok, header_crc_ok,
    output wire [11:0] header_payload_bytes,
    output wire [6:0] header_scrambler_seed,
    output wire [1:0] header_midamble_code,
    output wire header_error, header_busy,
    output wire frame_valid, capture_locked, capture_timeout,
    output wire [31:0] false_alarm_count,
    output wire replay_busy, replay_done, replay_error, fft_overflow,
    output wire phy_frame_done, output wire phy_frame_error,
    output wire [4:0] state_dbg,
    output wire fine_valid, output wire signed [31:0] fine_phase_inc
);
    wire payload_in_ready;
    wire phy_error;
    wire phy_llr_done;

    // Header_valid is a one-cycle decision pulse from the V2 Header path.
    // cofdm_payload_rx computes its own bounded codeword count from the
    // validated byte length, so it does not depend on the slower PHY counter.
    wire payload_start = header_valid && header_ok;
    wire payload_abort = rst || phy_error;

    cofdm_phy_rx_v2_top #(
      .BUFFER_DEPTH(BUFFER_DEPTH),
      .STF_TO_LTF_USEFUL(STF_TO_LTF_USEFUL),
      .PEAK_TO_BUFFER_OFFSET(PEAK_TO_BUFFER_OFFSET)
    ) phy (
      .clk,.rst,.sample_valid,.sample_re,.sample_im,.inv_noise_q16,
      .payload_ready(payload_in_ready),
      .payload_valid(payload_llr_valid),.payload_last(payload_llr_last),
      .payload_cw_first(payload_llr_cw_first),.payload_cw_last(payload_llr_cw_last),
      .payload_llr,
      .header_valid,.header_ok,.crc_ok(header_crc_ok),
      .payload_bytes(header_payload_bytes),.scrambler_seed(header_scrambler_seed),
      .midamble_code(header_midamble_code),.header_error,.header_busy,
      .frame_valid,.capture_locked,.capture_timeout,.false_alarm_count,
      .replay_busy,.replay_done,.replay_error,.fft_overflow,
      .frame_done(phy_llr_done),.frame_error(phy_error),.state_dbg,
      .fine_valid,.fine_phase_inc
    );

    cofdm_payload_rx #(.INPUT_SHIFT(INPUT_SHIFT)) payload (
      .clk,.rst,.start(payload_start),.abort_frame(payload_abort),
      .start_ready(),.payload_bytes(header_payload_bytes),
      .scrambler_seed(header_scrambler_seed),
      .in_valid(payload_llr_valid),.in_cw_first(payload_llr_cw_first),
      .in_cw_last(payload_llr_cw_last),.in_llr(payload_llr),
      .in_ready(payload_in_ready),
      .out_valid(payload_byte_valid),.out_ready(payload_byte_ready),
      .out_data(payload_byte),.out_last(payload_byte_last),
      .frame_done(payload_frame_done),.frame_error(payload_frame_error),
      .start_rejected(payload_start_rejected),.busy(payload_backend_busy),
      .crc_ok(payload_crc_ok),.padding_ok(payload_padding_ok),
      .ldpc_ok(payload_ldpc_ok),.decoder_iterations(payload_decoder_iterations),
      .codeword_index(payload_codeword_index)
    );

    assign phy_frame_done = phy_llr_done;
    assign phy_frame_error = phy_error;
endmodule
