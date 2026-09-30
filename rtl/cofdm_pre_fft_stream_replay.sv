`timescale 1ns/1ps
// Continuous write / bounded ring replay. Read-ahead is at most two words.
// A completed prefix can be extended without rewinding the read pointer.
// The writer cannot be stalled: overwrite is a fatal replay_error, not a
// request for unbounded memory. Indices use modulo-2^32 sample arithmetic;
// commands must refer to history less than 2^31 samples old.
module cofdm_pre_fft_stream_replay #(
    parameter integer IW=16,NFFT=256,CP_LEN=32,BUFFER_DEPTH=8192,
    parameter integer INDEX_W=32,SYMBOL_COUNT_W=16,SYMBOL_INDEX_W=8
)(
    input wire clk,rst,sample_valid,
    input wire signed [IW-1:0] sample_re,sample_im,
    input wire replay_start,input wire [INDEX_W-1:0] replay_start_index,
    input wire [SYMBOL_COUNT_W-1:0] replay_symbol_count,
    input wire replay_extend_valid,
    output wire out_valid,input wire out_ready,
    output wire signed [IW-1:0] out_re,out_im,
    output wire out_symbol_start,output wire [SYMBOL_INDEX_W-1:0] out_symbol_index,
    output wire replay_busy,replay_done,replay_error
);
    localparam AW=$clog2(BUFFER_DEPTH), SW=$clog2(NFFT+CP_LEN);
    localparam SPAN=NFFT+CP_LEN;
    reg [INDEX_W-1:0] write_count,read_index;
    reg [31:0] target,issued,delivered;
    reg [SW-1:0] sample_pos;
    reg [SYMBOL_INDEX_W-1:0] symbol_pos,pending_symbol,out_symbol;
    reg pending_start,out_start;
    reg active,pending,ov,done,err;
    reg [31:0] out_word;
    wire [31:0] requested=32'(replay_symbol_count)*32'(SPAN);
    wire [INDEX_W-1:0] age=write_count-read_index;
    wire available=age!=0 && !age[INDEX_W-1];
    wire overwritten=available && ((age>INDEX_W'(BUFFER_DEPTH)) ||
                                   (age==INDEX_W'(BUFFER_DEPTH) && sample_valid));
    wire slot=!ov || out_ready;
    wire issue=active && !replay_start && (!pending || slot) &&
               issued<target && available && !overwritten;
    wire [31:0] rd_word;
    cofdm_pre_fft_replay_mem #(.ADDR_W(AW),.DEPTH(BUFFER_DEPTH)) memory(
      .clk,.rst,.wr_en(sample_valid),.wr_addr(write_count[AW-1:0]),
      .wr_data({sample_im,sample_re}),.rd_en(issue),
      .rd_addr(read_index[AW-1:0]),.rd_data(rd_word));
    assign out_valid=ov;
    assign {out_im,out_re}=out_word;
    assign out_symbol_start=ov && out_start;
    assign out_symbol_index=out_symbol;
    assign replay_busy=active;
    assign replay_done=done;
    assign replay_error=err;
    initial begin
      if(IW!=16 || INDEX_W!=32) $error("Replay requires 16-bit IQ and 32-bit index");
      if((BUFFER_DEPTH&(BUFFER_DEPTH-1))!=0) $error("Ring depth must be power of two");
    end
    always @(posedge clk) begin
      if(rst) begin
        write_count<=0;read_index<=0;target<=0;issued<=0;delivered<=0;
        sample_pos<=0;symbol_pos<=0;pending_symbol<=0;out_symbol<=0;
        pending_start<=0;out_start<=0;active<=0;pending<=0;ov<=0;
        done<=0;err<=0;out_word<=0;
      end else begin
        done<=0;
        if(sample_valid) write_count<=write_count+1'b1;
        if(replay_start) begin
          read_index<=replay_start_index;target<=requested;issued<=0;delivered<=0;
          sample_pos<=0;symbol_pos<=0;pending<=0;ov<=0;err<=0;
          active<=requested!=0;done<=requested==0;
        end else begin
          if(replay_extend_valid && requested>target && !err) begin
            target<=requested;active<=1;
          end
          if(ov && out_ready) begin
            ov<=0;delivered<=delivered+1'b1;
            if(delivered+1==target && !(replay_extend_valid && requested>target)) begin
              active<=0;done<=1;
            end
          end
          if(pending && slot) begin
            ov<=1;out_word<=rd_word;out_start<=pending_start;
            out_symbol<=pending_symbol;pending<=0;
          end
          if(issue) begin
            pending<=1;pending_start<=sample_pos==0;pending_symbol<=symbol_pos;
            issued<=issued+1'b1;read_index<=read_index+1'b1;
            if(sample_pos==SW'(SPAN-1)) begin
              sample_pos<=0;symbol_pos<=symbol_pos+1'b1;
            end else sample_pos<=sample_pos+1'b1;
          end
          if(active && issued<target && overwritten) begin
            err<=1;active<=0;pending<=0;ov<=0;
          end
        end
      end
    end
endmodule
