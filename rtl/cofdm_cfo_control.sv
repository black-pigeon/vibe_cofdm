`timescale 1ns/1ps
// Latches the correction word used by the streaming NCO.  A new STF
// candidate clears phase and starts with zero correction; coarse CFO is then
// installed when the STF estimator finishes, and fine CFO replaces the word
// after the dual-LTF result is valid.  The phase increment is deliberately a
// level, so bubbles in downstream AXI streams do not disturb the oscillator.
module cofdm_cfo_control #(
    parameter integer PHASE_W = 32
) (
    input wire                         clk,
    input wire                         rst,
    input wire                         candidate_pulse,
    input wire                         coarse_valid,
    input wire signed [PHASE_W-1:0]    coarse_inc,
    input wire                         fine_valid,
    input wire signed [PHASE_W-1:0]    fine_inc,
    output reg signed [PHASE_W-1:0]    phase_inc,
    output reg                         clear_phase,
    output reg                         coarse_locked,
    output reg                         fine_locked
);
    always @(posedge clk) begin
        if (rst) begin
            phase_inc <= '0;
            clear_phase <= 1'b0;
            coarse_locked <= 1'b0;
            fine_locked <= 1'b0;
        end else begin
            clear_phase <= candidate_pulse;
            if (candidate_pulse) begin
                phase_inc <= '0;
                coarse_locked <= 1'b0;
                fine_locked <= 1'b0;
            end
            if (coarse_valid) begin
                phase_inc <= coarse_inc;
                coarse_locked <= 1'b1;
                fine_locked <= 1'b0;
            end
            if (fine_valid) begin
                phase_inc <= phase_inc + fine_inc;
                fine_locked <= 1'b1;
            end
        end
    end
endmodule
