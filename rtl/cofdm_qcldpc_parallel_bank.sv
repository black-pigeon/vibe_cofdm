`timescale 1ns/1ps
// Replicated QC-LDPC decoder bank used for the XC7Z020 resource/throughput
// study.  The upstream dispatcher assigns complete 648-LLR codewords to an
// idle lane and asserts one lane_start per codeword.  Each lane retains the
// scalar decoder's ready/valid protocol and can therefore be connected to a
// small per-lane FIFO or a round-robin codeword scheduler.
//
// This bank intentionally has no hidden inter-lane RAM or arbitration.  That
// keeps synthesis results honest: LANES is the number of actual decoder cores,
// while the dispatcher/FIFO cost can be measured separately when integrated.
module cofdm_qcldpc_parallel_bank #(
    parameter integer LANES=3,
    parameter integer MAX_ITERS=12
)(
    input wire clk,
    input wire rst,
    input wire [LANES-1:0] lane_start,
    input wire [LANES-1:0] lane_in_valid,
    input wire [LANES-1:0] lane_in_last,
    input wire signed [LANES*7-1:0] lane_in_llr,
    output wire [LANES-1:0] lane_in_ready,
    output wire [LANES-1:0] lane_out_valid,
    input wire [LANES-1:0] lane_out_ready,
    output wire [LANES-1:0] lane_out_last,
    output wire [LANES-1:0] lane_out_bit,
    output wire [LANES-1:0] lane_done,
    output wire [LANES-1:0] lane_decode_ok,
    output wire [LANES-1:0] lane_syndrome_ok,
    output wire [LANES*5-1:0] lane_iterations,
    output wire [LANES-1:0] lane_frame_error,
    output wire [LANES-1:0] lane_busy
);
    genvar g;
    generate
        for (g=0; g<LANES; g=g+1) begin : GEN_LANE
            cofdm_qcldpc_648_decoder #(.MAX_ITERS(MAX_ITERS)) decoder (
                .clk(clk), .rst(rst), .start(lane_start[g]),
                .in_valid(lane_in_valid[g]), .in_last(lane_in_last[g]),
                .in_ready(lane_in_ready[g]),
                .in_llr(lane_in_llr[g*7 +: 7]),
                .out_valid(lane_out_valid[g]), .out_ready(lane_out_ready[g]),
                .out_last(lane_out_last[g]), .out_bit(lane_out_bit[g]),
                .done(lane_done[g]), .decode_ok(lane_decode_ok[g]),
                .syndrome_ok(lane_syndrome_ok[g]),
                .iterations_done(lane_iterations[g*5 +: 5]),
                .frame_error(lane_frame_error[g]), .busy(lane_busy[g])
            );
        end
    endgenerate
endmodule
