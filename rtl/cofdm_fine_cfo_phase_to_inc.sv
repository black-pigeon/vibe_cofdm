`timescale 1ns/1ps
// Convert the dual-LTF phase into the signed Q0.32 NCO increment used by
// cofdm_cfo_nco_rotator.  Input phase is Q3.29 radians.  For a 256-point
// symbol with 32-sample CP, phase/(2*pi*(NFFT+CP)) is the CFO in cycles per
// sample; the fixed-point gain below folds in the 2^32 NCO scale.  The
// output is the *correction* increment, hence its sign is negative for a
// positive measured CFO, matching ltf_process.finePhaseInc and the NCO API.
module cofdm_fine_cfo_phase_to_inc #(
    parameter integer PHASE_W = 32,
    parameter integer INC_W = 32,
    parameter integer NFFT = 256,
    parameter integer CP_LEN = 32,
    parameter integer GAIN_SHIFT = 24,
    // round((8/(2*pi*(NFFT+CP_LEN))) * 2^GAIN_SHIFT)
    parameter integer GAIN_Q = 74172
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         in_valid,
    input  wire signed [PHASE_W-1:0]     in_phase,
    output reg                          out_valid,
    output reg signed [INC_W-1:0]       out_phase_inc
);
    localparam integer PROD_W = PHASE_W + 32;
    wire signed [PROD_W-1:0] product = $signed(in_phase) * $signed(GAIN_Q);
    wire signed [INC_W-1:0] scaled = INC_W'(product >>> GAIN_SHIFT);

    always @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_phase_inc <= '0;
        end else begin
            out_valid <= in_valid;
            if (in_valid)
                out_phase_inc <= -scaled;
        end
    end
endmodule
