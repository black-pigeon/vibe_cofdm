`timescale 1ns/1ps
// Serial MATLAB mapper-order LLRs (negative carriers first, I then Q).
// Write address = 13*k mod 384. NOT a natural-FFT-bin input interface.
// A start pulse in IDLE reserves one symbol. Early/missing TLAST discards it.
// One synchronous block RAM, held output under backpressure, no DSP/divider.
module cofdm_llr_deinterleaver #(
    parameter integer DATA_BITS=384, parameter integer LLR_W=16
)(
    input wire clk,rst,start,in_valid,in_last,
    output wire in_ready,
    input wire signed [LLR_W-1:0] in_llr,
    output reg out_valid, input wire out_ready,
    output reg out_last, output reg signed [LLR_W-1:0] out_llr,
    output wire busy, output reg frame_error
);
    localparam integer AW=$clog2(DATA_BITS);
    localparam [AW-1:0] LAST=AW'(DATA_BITS-1), WRAP=AW'(DATA_BITS-13);
    localparam [1:0] IDLE=0, WRITE=1, PREFETCH=2, READ=3;
    reg [1:0] state;
    reg [AW-1:0] count,addr,rd;
    (* ram_style="block" *) reg signed [LLR_W-1:0] mem[0:DATA_BITS-1];
    assign in_ready=(state==WRITE);
    assign busy=(state!=IDLE);
    initial if(DATA_BITS!=384) $error("Only the 384-bit QPSK profile is supported");
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE; count<=0; addr<=0; rd<=0;
            out_valid<=0; out_last<=0; out_llr<=0; frame_error<=0;
        end else begin
            frame_error<=0;
            if(start && state==IDLE) begin state<=WRITE; count<=0; addr<=0; end
            if(in_valid && in_ready) begin
                mem[addr]<=in_llr;
                if(in_last!=(count==LAST)) begin state<=IDLE; frame_error<=1; end
                else if(count==LAST) begin state<=PREFETCH; rd<=0; end
                else begin
                    count<=count+1'b1;
                    addr<=(addr>=WRAP)?addr-WRAP:addr+AW'(13);
                end
            end
            if(state==PREFETCH) begin
                out_llr<=mem[0]; out_valid<=1; out_last<=0; rd<=1; state<=READ;
            end
            if(state==READ && out_ready) begin
                if(out_last) begin out_valid<=0; out_last<=0; state<=IDLE; end
                else begin out_llr<=mem[rd]; out_last<=(rd==LAST); rd<=rd+1'b1; end
            end
        end
    end
endmodule
