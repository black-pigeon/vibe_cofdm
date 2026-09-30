`timescale 1ns/1ps
// Places the v2 Header decision in front of payload delivery.  Header LLRs
// are consumed by the Viterbi/CRC block; payload LLRs are held at the FIFO
// boundary until header_ok supplies a bounded n_codewords count to the upper
// controller.  This prevents a malformed length from causing unbounded RAM.
module cofdm_v2_rx_header_path #(parameter integer LLR_W=16,
                                 parameter integer GATE_CONFIG=0)(
    input wire clk,rst,frame_start,
    input wire stream_valid,input wire stream_header,input wire stream_last,
    input wire stream_cw_first,input wire stream_cw_last,
    input wire config_ready,
    input wire signed [LLR_W-1:0] stream_llr,output wire stream_ready,
    output wire payload_valid,output wire payload_last,
    output wire payload_cw_first,output wire payload_cw_last,
    output wire signed [LLR_W-1:0] payload_llr,input wire payload_ready,
    output wire header_valid,header_ok,crc_ok,
    output wire [11:0] payload_bytes,output wire [6:0] scrambler_seed,
    output wire [1:0] midamble_code,output wire header_error,output wire busy
);
    reg start_pending;
    reg header_accepted;
    reg header_pending;
    wire decoder_ready;
    wire decoder_start=start_pending;
    assign stream_ready=stream_header ? decoder_ready :
        (header_accepted && payload_ready);
    assign payload_valid=stream_valid && !stream_header && header_accepted;
    assign payload_last=stream_last && payload_valid;
    assign payload_cw_first=stream_cw_first && payload_valid;
    assign payload_cw_last=stream_cw_last && payload_valid;
    assign payload_llr=stream_llr;
    cofdm_v2_header_decoder_tdm #(.LLR_W(LLR_W)) decoder(
        .clk,.rst(rst|frame_start),.start(decoder_start),
        .in_valid(stream_valid && stream_header),.in_last(stream_last),
        .in_ready(decoder_ready),.in_llr(stream_llr),
        .header_valid,.header_ok,.payload_bytes,.scrambler_seed,.midamble_code,
        .crc_ok,.header_error,.busy);
    localparam CONFIG_GATE = (GATE_CONFIG != 0);
    wire config_gate = CONFIG_GATE ? config_ready : 1'b1;
    always @(posedge clk) begin
        if(rst) begin start_pending<=0; header_accepted<=0; header_pending<=0; end
        else if(frame_start) begin start_pending<=1; header_accepted<=0; header_pending<=0; end
        else begin
            start_pending<=0;
            if(header_valid) header_pending<=header_ok;
            if ((header_pending || header_valid) && header_ok && config_gate) begin
                header_accepted<=1'b1;
                header_pending<=1'b0;
            end
        end
    end
endmodule
