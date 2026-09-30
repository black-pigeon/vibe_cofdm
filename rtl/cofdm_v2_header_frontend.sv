`timescale 1ns/1ps
// Header-only integration boundary. The packetizer output is already
// descrambled by PRBS31; this wrapper collects exactly one 192-LLR Header
// symbol and starts the resource-shared Viterbi decoder.
module cofdm_v2_header_frontend #(parameter integer LLR_W=16)(
    input wire clk,rst,frame_start,
    input wire in_valid,input wire in_last,input wire signed [LLR_W-1:0] in_llr,
    output wire in_ready,
    output wire header_valid,header_ok,crc_ok,
    output wire [11:0] payload_bytes,output wire [6:0] scrambler_seed,
    output wire [1:0] midamble_code,output wire header_error,output wire busy
);
    reg start_pending;
    wire dec_start=start_pending;
    cofdm_v2_header_decoder #(.LLR_W(LLR_W)) decoder(
        .clk,.rst(rst|frame_start),.start(dec_start),
        .in_valid,.in_last,.in_ready,.in_llr,
        .header_valid,.header_ok,.payload_bytes,.scrambler_seed,.midamble_code,
        .crc_ok,.header_error,.busy);
    always @(posedge clk) begin
        if(rst) start_pending<=1'b0;
        else if(frame_start) start_pending<=1'b1;
        else start_pending<=1'b0;
    end
endmodule
