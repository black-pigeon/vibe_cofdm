`timescale 1ns/1ps
// x^7+x^4+1 pilot sign generator.
//
// The state is continuous over a frame.  One request consumes one PRBS bit;
// the eight requests belonging to each OFDM symbol therefore implement
// cofdm.pilot_values() without multiplying by symbolIndex or storing a ROM.
// frame_start must precede the first pilot request by at least one clock.
module cofdm_pilot_prbs #(
    parameter [6:0] SEED = 7'd53
) (
    input  wire clk, input wire rst,
    input  wire frame_start,
    input  wire pilot_valid,
    output reg  pilot_sign,
    output reg  pilot_out_valid
);
  reg [6:0] state;
  wire feedback = state[0] ^ state[3];
  wire [6:0] next_state = {feedback,state[6:1]};

  always @(posedge clk) begin
    if (rst) begin
      state <= SEED;
      pilot_sign <= 1'b0;
      pilot_out_valid <= 1'b0;
    end else begin
      pilot_out_valid <= 1'b0;
      if (frame_start) state <= SEED;
      else if (pilot_valid) begin
        // Same convention as pilot_phase_accum: 0 = +1, 1 = -1.
        pilot_sign <= state[0];
        pilot_out_valid <= 1'b1;
        state <= next_state;
      end
    end
  end
endmodule
