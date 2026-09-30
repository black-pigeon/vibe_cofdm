`timescale 1ns/1ps
// Symbol-sized storage converts natural FFT bin LLR pairs to MATLAB order.
// Header: reorder -> PRBS31 sign correction -> header decoder interface.
// Payload: reorder -> inverse interleave -> 648-LLR codeword framing.
// Payload scrambling is BEFORE LDPC encoding and MUST be undone AFTER decode.
// n_codewords is supplied by a validated header/controller, not inferred here.
// Two synchronous 192 x LLR_W banks, output holds through arbitrary stalls.
module cofdm_llr_packetizer #(parameter integer LLR_W=16)(
    input wire clk,rst,frame_start,
    input wire [15:0] n_codewords,
    input wire symbol_start,symbol_header,
    output wire symbol_ready,
    input wire in_valid,in_last,input wire [7:0] in_bin,
    input wire signed [LLR_W-1:0] in_re,in_im,
    output reg out_valid,input wire out_ready,
    output reg signed [LLR_W-1:0] out_llr,
    output reg out_header,out_symbol_last,out_cw_first,out_cw_last,
    output reg symbol_done,output reg frame_error
);
    localparam [1:0] IDLE=0,STORE=1,READ=2,HOLD=3;
    localparam signed [LLR_W-1:0] MIN_LLR={1'b1,{(LLR_W-1){1'b0}}};
    localparam signed [LLR_W-1:0] MAX_LLR={1'b0,{(LLR_W-1){1'b1}}};
    reg [1:0] state;
    reg header_q;
    reg [7:0] stored;
    reg [8:0] out_count,map_bit;
    reg [9:0] cw_bit;
    reg [15:0] cw_count;
    reg [6:0] scrambler;
    (* ram_style="block" *) reg signed [LLR_W-1:0] re_mem[0:191],im_mem[0:191];
    reg signed [LLR_W-1:0] raw;
    reg raw_odd,raw_scramble;
    // Memory output register is deliberately outside reset for BRAM inference.
    wire [7:0] rd_rank=header_q?out_count[7:0]:map_bit[8:1];
    wire payload_done=(cw_count>=n_codewords);
    function automatic is_data(input [7:0] b);
        begin
            case(b)
                13,39,65,91,165,191,217,243:is_data=0;
                default:is_data=(b>=1 && b<=100)||(b>=156);
            endcase
        end
    endfunction
    function automatic [7:0] rank(input [7:0] b);
        reg [7:0] r;
        begin
            if(b>=156) begin
                r=b-8'd156;
                if(b>165) r=r-1'b1; if(b>191) r=r-1'b1;
                if(b>217) r=r-1'b1; if(b>243) r=r-1'b1;
            end else begin
                r=b+8'd95;
                if(b>13) r=r-1'b1; if(b>39) r=r-1'b1;
                if(b>65) r=r-1'b1; if(b>91) r=r-1'b1;
            end
            rank=r;
        end
    endfunction
    reg signed [LLR_W-1:0] re_read,im_read;
    always @(posedge clk) begin
        if(state==STORE && in_valid && is_data(in_bin)) begin
            re_mem[rank(in_bin)]<=in_re; im_mem[rank(in_bin)]<=in_im;
        end
        if(state==READ) begin
            re_read<=re_mem[rd_rank]; im_read<=im_mem[rd_rank];
        end
    end
    always @* begin
        raw=raw_odd?im_read:re_read;
        out_llr=raw;
        if(raw_scramble) out_llr=(raw==MIN_LLR)?MAX_LLR:-raw;
    end
    assign symbol_ready=(state==IDLE) && !frame_start && !rst;
    always @(posedge clk) begin
        if(rst || frame_start) begin
            state<=IDLE; stored<=0; header_q<=0; out_count<=0; map_bit<=0;
            cw_bit<=0; cw_count<=0; scrambler<=31;
            out_valid<=0; out_header<=0; out_symbol_last<=0;
            out_cw_first<=0; out_cw_last<=0; symbol_done<=0; frame_error<=0;
            raw_odd<=0; raw_scramble<=0;
        end else begin
            symbol_done<=0; frame_error<=0;
            if(symbol_start && symbol_ready) begin
                state<=STORE; stored<=0; header_q<=symbol_header;
            end
            if(state==STORE && in_valid) begin
                if(!is_data(in_bin) || in_last!=(stored==191)) begin
                    frame_error<=1; state<=IDLE;
                end else if(stored==191) begin
                    state<=READ; out_count<=0; map_bit<=0;
                end else stored<=stored+1'b1;
            end
            if(state==READ) begin
                if(!header_q && payload_done) begin state<=IDLE; symbol_done<=1; end
                else begin
                    raw_odd<=!header_q && map_bit[0]; raw_scramble<=header_q && scrambler[0];
                    out_valid<=1; out_header<=header_q;
                    out_symbol_last<=header_q?(out_count==191):(out_count==383 || (cw_count+1'b1==n_codewords && cw_bit==647));
                    out_cw_first<=!header_q && cw_bit==0;
                    out_cw_last<=!header_q && cw_bit==647;
                    state<=HOLD;
                end
            end
            if(state==HOLD && out_valid && out_ready) begin
                out_valid<=0;
                if(header_q) scrambler<={scrambler[0]^scrambler[3],scrambler[6:1]};
                else if(cw_bit==647) begin cw_bit<=0; cw_count<=cw_count+1'b1; end
                else cw_bit<=cw_bit+1'b1;
                if(out_symbol_last) begin state<=IDLE; symbol_done<=1; end
                else begin
                    state<=READ; out_count<=out_count+1'b1;
                    // 325 is 13^-1 mod 384; add and conditional subtract.
                    map_bit<=(map_bit>=59)?map_bit-9'd59:map_bit+9'd325;
                end
            end
        end
    end
endmodule
