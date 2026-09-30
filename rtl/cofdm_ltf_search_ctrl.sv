`timescale 1ns/1ps
// Schedules the short LTF matcher window from an STF candidate.  The
// controller waits until the nominal LTF useful-sample position minus
// SEARCH_RADIUS, then emits a one-cycle marker before the first sample.
module cofdm_ltf_search_ctrl #(
    parameter integer INDEX_W = 32,
    parameter integer STF_TO_LTF_USEFUL = 192,
    parameter integer SEARCH_RADIUS = 8,
    parameter integer TIMER_W = 16
) (
    input wire                         clk,
    input wire                         rst,
    input wire                         sample_valid,
    input wire                         stf_hit,
    input wire [INDEX_W-1:0]           stf_index,
    input wire                         search_done,
    output reg                         search_start,
    output reg [INDEX_W-1:0]           search_base_index,
    output reg                         search_pending,
    output reg                         search_error
);
    localparam integer DELAY = STF_TO_LTF_USEFUL-SEARCH_RADIUS;
    localparam [TIMER_W-1:0] LAST_WAIT = TIMER_W'(DELAY-1);
    reg [TIMER_W-1:0] wait_count;
    reg [INDEX_W-1:0] candidate_index;
    reg waiting;
    always @(posedge clk) begin
        if (rst) begin
            search_start <= 1'b0; search_base_index <= '0; search_pending <= 1'b0;
            search_error <= 1'b0; wait_count <= '0; candidate_index <= '0; waiting <= 1'b0;
        end else begin
            search_start <= 1'b0;
            // The matcher owns the long scan. Release the transaction guard
            // only after its peak or timeout event so a later frame can be
            // acquired without resetting the whole PHY.
            if (search_done) waiting <= 1'b0;
            if (stf_hit && !waiting && !search_pending) begin
                candidate_index <= stf_index;
                search_pending <= 1'b1;
                wait_count <= '0;
                search_error <= 1'b0;
            end
            if (search_pending && sample_valid) begin
                if (wait_count == LAST_WAIT) begin
                    search_base_index <= candidate_index + INDEX_W'(DELAY);
                    search_start <= 1'b1;
                    search_pending <= 1'b0;
                    waiting <= 1'b1;
                    wait_count <= '0;
                end else begin
                    wait_count <= wait_count + 1'b1;
                end
            end
            // Candidates during the active matcher scan are expected to be
            // ignored (the LTF itself can resemble an STF). A collision is
            // actionable only while the scheduler is still waiting to start.
            if (stf_hit && search_pending) search_error <= 1'b1;
        end
    end
endmodule
