`timescale 1ns/1ps
// Multi-stage PHY capture controller.
// STF is a candidate only. A legal, strong LTF peak, valid fine CFO, and
// a good PHY-header CRC are required before capture_locked is asserted.
// All event inputs are streaming pulses; timers advance on sample_valid.
module cofdm_capture_ctrl #(
    parameter integer INDEX_W=32,
    parameter integer SCORE_W=16,
    parameter integer TIMER_W=16,
    parameter integer LTF_SCORE_MIN=32'h00001EB8, // 0.12 in Q0.16
    parameter integer LTF_MIN_OFFSET=64,
    parameter integer LTF_MAX_OFFSET=384,
    parameter integer LTF_TO_FRAME_OFFSET=192,
    parameter integer LTF_TIMEOUT=512,
    parameter integer FINE_TIMEOUT=128,
    parameter integer HEADER_TIMEOUT=512,
    parameter integer HOLDOFF=256,
    parameter integer LOCK_TIMEOUT=65535
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     sample_valid,
    input  wire                     stf_hit,
    input  wire [INDEX_W-1:0]       stf_index,
    input  wire                     ltf_peak_valid,
    input  wire [SCORE_W-1:0]       ltf_peak_score,
    input  wire [INDEX_W-1:0]       ltf_peak_index,
    input  wire                     fine_cfo_valid,
    input  wire                     header_crc_valid,
    input  wire                     header_crc_ok,
    input  wire                     frame_abort,
    input  wire                     frame_done,
    output reg                      candidate_valid,
    output reg                      coarse_cfo_enable,
    output reg                      ltf_start,
    output reg                      fine_cfo_enable,
    output reg                      header_enable,
    output reg                      frame_start,
    output reg                      frame_valid,
    output reg                      capture_locked,
    output reg                      capture_timeout,
    output reg [31:0]               false_alarm_count,
    output reg [INDEX_W-1:0]        frame_start_index,
    output reg [INDEX_W-1:0]        ltf_start_index,
    output reg [2:0]                state_dbg
);
    localparam [2:0] S_IDLE=3'd0, S_LTF=3'd1, S_FINE=3'd2,
                     S_HEADER=3'd3, S_LOCKED=3'd4, S_HOLDOFF=3'd5;
    localparam integer TW = (TIMER_W < 2) ? 2 : TIMER_W;
    reg [2:0] state;
    reg [TW-1:0] timer;
    reg [TW-1:0] hold_timer;
    reg [INDEX_W-1:0] candidate_index;
    wire ltf_position_ok = (ltf_peak_index >= candidate_index + LTF_MIN_OFFSET) &&
                           (ltf_peak_index <= candidate_index + LTF_MAX_OFFSET);
    wire ltf_score_ok = (ltf_peak_score >= SCORE_W'(LTF_SCORE_MIN));
    wire timer_ltf_expired = (timer >= TW'(LTF_TIMEOUT));
    wire timer_fine_expired = (timer >= TW'(FINE_TIMEOUT));
    wire timer_header_expired = (timer >= TW'(HEADER_TIMEOUT));
    wire timer_lock_expired = (timer >= TW'(LOCK_TIMEOUT));
    wire timer_holdoff_expired = (hold_timer >= TW'(HOLDOFF));

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; timer <= '0; hold_timer <= '0;
            candidate_index <= '0; frame_start_index <= '0; ltf_start_index <= '0;
            candidate_valid <= 1'b0; coarse_cfo_enable <= 1'b0;
            ltf_start <= 1'b0; fine_cfo_enable <= 1'b0;
            header_enable <= 1'b0; frame_start <= 1'b0; frame_valid <= 1'b0;
            capture_locked <= 1'b0; capture_timeout <= 1'b0;
            false_alarm_count <= 32'd0; state_dbg <= S_IDLE;
        end else begin
            // Every output except the level signals is a one-cycle event.
            candidate_valid <= 1'b0; coarse_cfo_enable <= 1'b0;
            ltf_start <= 1'b0; fine_cfo_enable <= 1'b0;
            frame_start <= 1'b0; frame_valid <= 1'b0;
            capture_timeout <= 1'b0;
            header_enable <= (state == S_HEADER) && sample_valid;
            capture_locked <= (state == S_LOCKED);

            begin
                case (state)
                    S_IDLE: begin
                        timer <= '0; hold_timer <= '0;
                        if (stf_hit) begin
                            candidate_index <= stf_index;
                            candidate_valid <= 1'b1;
                            coarse_cfo_enable <= 1'b1;
                            timer <= '0; state <= S_LTF;
                        end
                    end
                    S_LTF: begin
                        if (sample_valid) timer <= timer + 1'b1;
                        if (ltf_peak_valid) begin
                            if (ltf_position_ok && ltf_score_ok) begin
                                ltf_start_index <= ltf_peak_index;
                                frame_start_index <= ltf_peak_index - LTF_TO_FRAME_OFFSET;
                                ltf_start <= 1'b1;
                                fine_cfo_enable <= 1'b1;
                                frame_start <= 1'b1;
                                timer <= '0; state <= S_FINE;
                            end else begin
                                false_alarm_count <= false_alarm_count + 1'b1;
                                timer <= '0; hold_timer <= '0; state <= S_HOLDOFF;
                            end
                        end else if (timer_ltf_expired) begin
                            false_alarm_count <= false_alarm_count + 1'b1;
                            capture_timeout <= 1'b1;
                            timer <= '0; hold_timer <= '0; state <= S_HOLDOFF;
                        end
                    end
                    S_FINE: begin
                        if (sample_valid) timer <= timer + 1'b1;
                        if (fine_cfo_valid) begin
                            timer <= '0; state <= S_HEADER;
                        end else if (timer_fine_expired) begin
                            false_alarm_count <= false_alarm_count + 1'b1;
                            capture_timeout <= 1'b1;
                            timer <= '0; hold_timer <= '0; state <= S_HOLDOFF;
                        end
                    end
                    S_HEADER: begin
                        if (sample_valid) timer <= timer + 1'b1;
                        if (header_crc_valid) begin
                            if (header_crc_ok) begin
                                frame_valid <= 1'b1;
                                timer <= '0; state <= S_LOCKED;
                            end else begin
                                false_alarm_count <= false_alarm_count + 1'b1;
                                timer <= '0; hold_timer <= '0; state <= S_HOLDOFF;
                            end
                        end else if (timer_header_expired) begin
                            false_alarm_count <= false_alarm_count + 1'b1;
                            capture_timeout <= 1'b1;
                            timer <= '0; hold_timer <= '0; state <= S_HOLDOFF;
                        end
                    end
                    S_LOCKED: begin
                        capture_locked <= 1'b1;
                        if (sample_valid) timer <= timer + 1'b1;
                        if (frame_abort || frame_done || timer_lock_expired) begin
                            timer <= '0; hold_timer <= '0; state <= S_HOLDOFF;
                        end
                    end
                    S_HOLDOFF: begin
                        if (sample_valid) hold_timer <= hold_timer + 1'b1;
                        if (timer_holdoff_expired) begin
                            hold_timer <= '0; timer <= '0; state <= S_IDLE;
                        end
                    end
                    default: begin state <= S_IDLE; timer <= '0; hold_timer <= '0; end
                endcase
            end
            state_dbg <= state;
        end
    end
endmodule
