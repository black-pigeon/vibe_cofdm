`timescale 1ns/1ps
// Bounded codeword FIFO and scheduler for the replicated 648-bit cores.
//
// This is an integration/performance step: it does not claim intra-codeword
// QC parallelism.  Complete codewords are buffered in BRAM, assigned to the
// first idle decoder lane, and decoder output is released in input order.
// A later QC-subblock core can use the same FIFO and ordering interface.
module cofdm_qcldpc_codeword_scheduler #(
    parameter integer LANES=3,
    parameter integer FIFO_DEPTH=LANES+1,
    parameter integer MAX_ITERS=12
)(
    input wire clk, input wire rst,
    input wire in_valid, output wire in_ready,
    input wire in_last, input wire signed [6:0] in_llr,
    output wire out_valid, input wire out_ready,
    output wire out_last, output wire out_bit,
    output wire out_decode_ok, output wire [4:0] out_iterations,
    output wire [15:0] out_codeword_index,
    output reg codeword_done, output reg frame_error,
    output wire busy, output wire [15:0] queued_codewords
);
    localparam integer SLOT_W=(FIFO_DEPTH<=1)?1:$clog2(FIFO_DEPTH);
    localparam integer POS_W=10;
    localparam integer CNT_W=$clog2(FIFO_DEPTH+1);
    localparam integer SEQ_W=16;
    localparam integer LANE_W=(LANES<=1)?1:$clog2(LANES);
    localparam [CNT_W-1:0] FIFO_DEPTH_CONST=CNT_W'(FIFO_DEPTH);
    (* ram_style="block" *) reg signed [6:0] cw_mem [0:FIFO_DEPTH*648-1];
    reg [POS_W-1:0] in_pos;
    reg [SLOT_W-1:0] wr_slot,rd_slot;
    reg [CNT_W-1:0] fifo_count;
    reg [SEQ_W-1:0] head_seq,assign_seq[0:LANES-1],next_out_seq;
    reg [SLOT_W-1:0] lane_slot[0:LANES-1];
    reg [POS_W-1:0] lane_pos[0:LANES-1];
    reg lane_assigned[0:LANES-1],lane_feed[0:LANES-1];
    reg signed [6:0] lane_data[0:LANES-1];
    reg lane_data_valid[0:LANES-1];
    reg [LANES-1:0] lane_start;
    wire [LANES-1:0] lane_ready,lane_ov,lane_ol,lane_ob,lane_done,lane_ok;
    wire [LANES*5-1:0] lane_it;
    wire [LANES*7-1:0] lane_llr;
    wire [LANES-1:0] lane_in_valid,lane_in_last,lane_out_ready;
    wire [LANES-1:0] lane_assigned_vec;
    wire push_word = in_valid && in_ready && in_last && (in_pos==10'd647);
    wire dispatch_possible = (fifo_count != 0);
    integer i,j;
    reg dispatch;
    reg [LANE_W-1:0] dispatch_lane;
    reg have_output;
    reg [LANES-1:0] output_select;

    assign in_ready = !rst && (fifo_count < FIFO_DEPTH_CONST) && !frame_error;
    assign queued_codewords = {{(16-CNT_W){1'b0}},fifo_count};
    assign busy = (fifo_count != 0) || (|lane_assigned_vec) || (in_pos != 0);

    // Select one idle lane per cycle. Output ordering is enforced separately.
    always @* begin
        dispatch=1'b0; dispatch_lane=0;
        if(dispatch_possible) begin
            for(j=0;j<LANES;j=j+1) begin
                if(!dispatch && !lane_assigned[j]) begin
                    dispatch=1'b1; dispatch_lane=LANE_W'(j);
                end
            end
        end
        have_output=1'b0; output_select='0;
        for(j=0;j<LANES;j=j+1) begin
            if(!have_output && lane_assigned[j] && assign_seq[j]==next_out_seq && lane_ov[j]) begin
                have_output=1'b1; output_select[j]=1'b1;
            end
        end
    end
    // The FIFO memory is read synchronously. This is intentional: it permits
    // Vivado to infer BRAM (one read stream per active decoder lane) instead
    // of turning the bounded store into a large asynchronous LUTRAM.
    genvar g;
    generate for(g=0;g<LANES;g=g+1) begin : G
        assign lane_assigned_vec[g]=lane_assigned[g];
        assign lane_in_valid[g]=lane_feed[g] && lane_data_valid[g];
        assign lane_in_last[g]=lane_feed[g] && (lane_pos[g]==10'd647);
        assign lane_llr[g*7 +: 7]=lane_data[g];
        assign lane_out_ready[g]=out_ready && output_select[g];
    end endgenerate
    assign out_valid=have_output;
    // The selected lane's last/bit/status are reduced through the one-hot mask.
    reg selected_last,selected_bit,selected_ok; reg [4:0] selected_it; reg [15:0] selected_seq;
    always @* begin
        selected_last=0;selected_bit=0;selected_ok=0;selected_it=0;selected_seq=0;
        for(j=0;j<LANES;j=j+1) if(output_select[j]) begin
            selected_last=lane_ol[j];selected_bit=lane_ob[j];selected_ok=lane_ok[j];
            selected_it=lane_it[j*5 +: 5];selected_seq=assign_seq[j];
        end
    end
    assign out_last=selected_last; assign out_bit=selected_bit;
    assign out_decode_ok=selected_ok;assign out_iterations=selected_it;
    assign out_codeword_index=selected_seq;

    /* verilator lint_off PINCONNECTEMPTY */
    cofdm_qcldpc_parallel_bank #(.LANES(LANES),.MAX_ITERS(MAX_ITERS)) bank(
        .clk,.rst,.lane_start,.lane_in_valid,.lane_in_last,.lane_in_llr(lane_llr),
        .lane_in_ready(lane_ready),.lane_out_valid(lane_ov),.lane_out_ready(lane_out_ready),
        .lane_out_last(lane_ol),.lane_out_bit(lane_ob),.lane_done(lane_done),
        .lane_decode_ok(lane_ok),.lane_syndrome_ok(),
        .lane_iterations(lane_it),.lane_frame_error(),.lane_busy());
    /* verilator lint_on PINCONNECTEMPTY */

    always @(posedge clk) begin
        if(rst) begin
            in_pos<=0;wr_slot<=0;rd_slot<=0;fifo_count<=0;head_seq<=0;next_out_seq<=0;
            lane_start<='0;frame_error<=0;codeword_done<=0;
            for(i=0;i<LANES;i=i+1) begin lane_assigned[i]<=0;lane_feed[i]<=0;lane_pos[i]<=0;lane_slot[i]<=0;lane_data[i]<=0;lane_data_valid[i]<=0;assign_seq[i]<=0;end
        end else begin
            lane_start<='0;codeword_done<=0;
            if(in_valid && in_ready) begin
                cw_mem[wr_slot*648+in_pos]<=in_llr;
                if(in_last != (in_pos==10'd647)) begin frame_error<=1;end
                if(in_pos==10'd647) begin in_pos<=0;wr_slot<=wr_slot+1'b1;end
                else in_pos<=in_pos+1'b1;
            end
            if(dispatch) begin
                lane_assigned[dispatch_lane]<=1;lane_feed[dispatch_lane]<=1;lane_pos[dispatch_lane]<=0;lane_data_valid[dispatch_lane]<=0;
                lane_slot[dispatch_lane]<=rd_slot;assign_seq[dispatch_lane]<=head_seq;head_seq<=head_seq+1'b1;
                lane_start[dispatch_lane]<=1;rd_slot<=rd_slot+1'b1;
            end
            for(i=0;i<LANES;i=i+1) begin
                if(lane_feed[i] && !lane_data_valid[i]) begin
                    lane_data[i]<=cw_mem[lane_slot[i]*648+lane_pos[i]];
                    lane_data_valid[i]<=1;
                end else if(lane_feed[i] && lane_data_valid[i] && lane_ready[i]) begin
                    if(lane_pos[i]==10'd647) begin lane_feed[i]<=0;lane_data_valid[i]<=0;end
                    else begin
                        lane_pos[i]<=lane_pos[i]+1'b1;
                        lane_data[i]<=cw_mem[lane_slot[i]*648+lane_pos[i]+1'b1];
                    end
                end
                if(lane_done[i]) begin lane_assigned[i]<=0;codeword_done<=1;end
            end
            if(push_word && !dispatch) fifo_count<=fifo_count+1'b1;
            else if(!push_word && dispatch) fifo_count<=fifo_count-1'b1;
            if(push_word && dispatch) fifo_count<=fifo_count;
            if(have_output && out_ready && selected_last) next_out_seq<=next_out_seq+1'b1;
        end
    end
endmodule
