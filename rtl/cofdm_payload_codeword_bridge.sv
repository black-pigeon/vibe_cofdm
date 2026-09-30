`timescale 1ns/1ps
// Input is ALREADY deinterleaved. in_last is an OFDM-symbol marker, never
// a codeword/frame marker. The decoder itself stores 648 LLRs; no duplicate
// codeword RAM here. A bounded upstream queue must cover the slow decoder.
module cofdm_payload_codeword_bridge #(
    parameter integer INPUT_LLR_W=16,
    parameter integer INPUT_SHIFT=4,
    parameter integer MAX_CODEWORDS=51
)(
    input wire clk,rst,frame_start,
    input wire [15:0] n_codewords,
    input wire in_valid,in_last,in_cw_first,in_cw_last,
    output wire in_ready, input wire signed [INPUT_LLR_W-1:0] in_llr,
    output wire out_valid, input wire out_ready, output wire out_last,out_bit,
    output reg codeword_done,frame_done,frame_error,
    output wire busy, output reg [15:0] codeword_index,
    output wire decoder_ok, output wire [4:0] decoder_iterations
);
    localparam [2:0] WAIT_CONFIG=0,START=1,SEND=2,DRAIN=3,FINISHED=4;
    reg [2:0] state;
    reg [9:0] count;
    wire dec_ready,dec_done,dec_error,dec_busy;
    wire take=in_valid && in_ready;
    function automatic signed [6:0] quantize_llr(input signed [INPUT_LLR_W-1:0] x);
        reg signed [INPUT_LLR_W-1:0] y;
        begin
            y = x >>> INPUT_SHIFT;
            if(y > 63) quantize_llr=7'sd63;
            else if(y < -63) quantize_llr=-7'sd63;
            else quantize_llr=y[6:0];
        end
    endfunction
    wire signed [6:0] q_in_llr=quantize_llr(in_llr);
    wire bad_marker=(in_cw_first!=(count==0)) || (in_cw_last!=(count==647));
    assign in_ready=(state==SEND) && dec_ready && !rst && !frame_start;
    assign busy=state!=WAIT_CONFIG && state!=FINISHED;
    /* verilator lint_off PINCONNECTEMPTY */
    cofdm_qcldpc_648_decoder decoder(.clk,.rst(rst|frame_start),.start(state==START),
        .in_valid(take && !bad_marker),.in_ready(dec_ready),.in_last(in_cw_last),.in_llr(q_in_llr),
        .out_valid,.out_ready,.out_last,.out_bit,.done(dec_done),.decode_ok(decoder_ok),
        .syndrome_ok(),.iterations_done(decoder_iterations),.frame_error(dec_error),.busy(dec_busy));
    /* verilator lint_on PINCONNECTEMPTY */
    // Deliberately unused OFDM symbol marker, retained to match upstream ABI.
    wire unused_symbol_last=in_last;
    always @(posedge clk) begin
        if(rst || frame_start) begin
            state<=WAIT_CONFIG;count<=0;codeword_index<=0;codeword_done<=0;frame_done<=0;frame_error<=0;
        end else begin
            codeword_done<=0;frame_done<=0;frame_error<=0;
            case(state)
            WAIT_CONFIG: if(n_codewords!=0) begin
                if(n_codewords>16'(MAX_CODEWORDS)) begin frame_error<=1;state<=FINISHED;end
                else state<=START;
            end
            START: begin state<=SEND;count<=0;end
            SEND: if(take) begin
                if(bad_marker) begin frame_error<=1;state<=FINISHED;end
                else if(count==647) state<=DRAIN;
                else count<=count+1'b1;
            end
            DRAIN: if(dec_done && !dec_busy) begin
                codeword_done<=1;
                if(!decoder_ok) begin frame_error<=1;state<=FINISHED;end
                else if(codeword_index+1'b1==n_codewords) begin frame_done<=1;state<=FINISHED;end
                else begin codeword_index<=codeword_index+1'b1;state<=START;end
            end
            default:begin end
            endcase
            if(dec_error) begin frame_error<=1;state<=FINISHED;end
        end
    end
endmodule
