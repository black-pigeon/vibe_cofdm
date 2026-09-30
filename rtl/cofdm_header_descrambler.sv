`timescale 1ns/1ps
// PHY-header LLR descrambler.  Multiplying an LLR by +/-1 is equivalent to
// XORing the corresponding hard bit.  The stream consumes the same x^7+x^4+1
// sequence as MATLAB header_v2/header handling (seed 31 by default).
module cofdm_header_descrambler #(
    parameter [6:0] SEED = 7'd31,
    parameter integer LLR_W = 16
) (
    input wire clk, input wire rst,
    input wire frame_start,
    input wire in_valid,
    input wire signed [LLR_W-1:0] in_llr,
    output wire in_ready,
    output reg out_valid,
    output reg signed [LLR_W-1:0] out_llr
);
  reg [6:0] state;
  wire feedback = state[0] ^ state[3];
  wire [6:0] next_state = {feedback,state[6:1]};
  localparam signed [LLR_W-1:0] MIN_LLR = {1'b1,{(LLR_W-1){1'b0}}};
  localparam signed [LLR_W-1:0] MAX_LLR = {1'b0,{(LLR_W-1){1'b1}}};

  assign in_ready = !frame_start && !rst;
  always @(posedge clk) begin
    if (rst) begin
      state <= SEED; out_valid <= 1'b0; out_llr <= '0;
    end else begin
      out_valid <= 1'b0;
      if (frame_start) state <= SEED;
      else if (in_valid && in_ready) begin
        out_valid <= 1'b1;
        if (state[0]) begin
          // Saturating negation protects the most-negative two's-complement
          // value, which otherwise cannot be represented after sign change.
          if (in_llr == MIN_LLR) out_llr <= MAX_LLR;
          else out_llr <= -in_llr;
        end else out_llr <= in_llr;
        state <= next_state;
      end
    end
  end
endmodule
