`timescale 1ns/1ps
// Integrated frequency-domain symbol/LLR boundary. H and inv_noise are
// calibrated upstream; header/data FFT frames are routed here by a controller.
// LTFs/midambles go to channel estimation instead. pilot_skip_midamble must
// pulse once when a midamble is consumed there. Frame_start flushes all state.
// Header output is pre-FEC soft information, not a Header CRC decision.
module cofdm_pre_ldpc_stream #(parameter integer LLR_W=16)(
    input wire clk,rst,frame_start,
    input wire h_load_valid,h_load_last,input wire [7:0] h_load_bin,
    input wire signed [17:0] h_load_re,h_load_im,output wire h_load_ready,
    input wire fft_valid,fft_last,input wire [7:0] fft_bin,
    input wire signed [15:0] fft_re,fft_im,output wire fft_ready,
    input wire symbol_header,pilot_skip_midamble,
    input wire [23:0] inv_noise_q16,input wire [15:0] n_codewords,
    output wire out_valid,input wire out_ready,output wire signed [LLR_W-1:0] out_llr,
    output wire out_header,out_symbol_last,out_cw_first,out_cw_last,
    output wire symbol_done,frame_error
);
    wire reset_frame=rst|frame_start;
    wire kr,pr,ps,lv,ll;
    wire [7:0] lb;
    wire signed [LLR_W-1:0] lr,li;
    reg collecting;
    wire pv,prdy,ph,psl,pcf,pcl;
    wire signed [LLR_W-1:0] pllr;
    wire accepted=fft_valid && fft_ready;
    wire begin_symbol=accepted && !collecting;
    assign fft_ready=kr && (collecting || pr) && !reset_frame;
    cofdm_symbol_pilots pilots(.clk,.rst,.frame_start,
        .advance((accepted && fft_last)||pilot_skip_midamble),.fft_bin,.pilot_sign(ps));
    cofdm_pre_ldpc_symbol #(.LLR_W(LLR_W)) kernel(
        .clk,.rst(reset_frame),.h_load_valid,.h_load_last,.h_load_bin,.h_load_re,.h_load_im,.h_load_ready,
        .fft_valid(accepted),.fft_last,.fft_bin,.fft_re,.fft_im,.fft_pilot_sign(ps),
        .symbol_mode_bpsk(symbol_header),.inv_noise_q16,.fft_ready(kr),
        .llr_valid(lv),.llr_last(ll),.llr_bin(lb),.llr_re(lr),.llr_im(li),
        .llr_saturated(),.phase_valid(),.phase(),.symbol_done(),.busy());
    cofdm_llr_packetizer #(.LLR_W(LLR_W)) packer(
        .clk,.rst,.frame_start,.n_codewords,.symbol_start(begin_symbol),.symbol_header,.symbol_ready(pr),
        .in_valid(lv),.in_last(ll),.in_bin(lb),.in_re(lr),.in_im(li),
        .out_valid(pv),.out_ready(prdy),.out_llr(pllr),.out_header(ph),
        .out_symbol_last(psl),.out_cw_first(pcf),.out_cw_last(pcl),
        .symbol_done,.frame_error);
    cofdm_llr_fifo #(.WIDTH(LLR_W+4)) fifo(.clk,.rst(reset_frame),
        .in_valid(pv),.in_ready(prdy),.in_data({pcl,pcf,psl,ph,pllr}),
        .out_valid,.out_ready,.out_data({out_cw_last,out_cw_first,out_symbol_last,out_header,out_llr}));
    always @(posedge clk) begin
        if(reset_frame) collecting<=0;
        else if(accepted) collecting<=!fft_last;
    end
endmodule
