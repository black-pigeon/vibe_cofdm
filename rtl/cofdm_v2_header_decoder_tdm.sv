`timescale 1ns/1ps
// Low-resource v2 Header Viterbi reference for XC7Z020.  One destination
// state is updated per clock; 54 trellis steps therefore take 3456 clocks.
// The arithmetic is shared and synthesizes to a small number of LUTs/FFs,
// while the 54x64 survivor bits remain in a compact RAM/register array.
module cofdm_v2_header_decoder_tdm #(
    parameter integer LLR_W=8,
    parameter integer METRIC_W=24,
    parameter integer MAX_PAYLOAD=2048
) (
    input wire clk,rst,start,input wire in_valid,input wire in_last,
    output wire in_ready,input wire signed [LLR_W-1:0] in_llr,
    output reg header_valid,header_ok,output reg [11:0] payload_bytes,
    output reg [6:0] scrambler_seed,output reg [1:0] midamble_code,
    output reg crc_ok,header_error,busy
);
    localparam [2:0] IDLE=0,COLLECT=1,ACS=2,TRACE=3,VALIDATE=4;
    localparam signed [METRIC_W-1:0] NEG={1'b1,{(METRIC_W-1){1'b0}}};
    reg [2:0] state; reg [7:0] in_count; reg [5:0] step,trace_step;
    reg [5:0] acs_dest,trace_state;
    reg acs_eval;
    reg [5:0] dest_q;
    reg signed [METRIC_W-1:0] cand0_q,cand1_q;
    reg signed [LLR_W-1:0] llr_mem[0:107];
    reg signed [METRIC_W-1:0] metric[0:63];
    reg signed [METRIC_W-1:0] metric_new[0:63];
    (* ram_style="block" *) reg [53:0] survivor_mem[0:63]; reg [53:0] decoded;
    integer i;
    function automatic [1:0] conv_out(input [5:0] prev,input bit u);
      reg [6:0] r; begin r={u,prev}; conv_out[1]=^(r&7'b1011011); conv_out[0]=^(r&7'b1111001); end
    endfunction
    function automatic signed [METRIC_W-1:0] bm(input [1:0] bits,input signed [LLR_W-1:0] a,input signed [LLR_W-1:0] b);
      reg signed [METRIC_W-1:0] x,y; begin
        x={{(METRIC_W-LLR_W){a[LLR_W-1]}},a}; y={{(METRIC_W-LLR_W){b[LLR_W-1]}},b};
        if(bits[0]) x=-x; if(bits[1]) y=-y; bm=x+y;
      end
    endfunction
    /* verilator lint_off UNUSED */
    function automatic [5:0] p0(input [5:0] s); p0={s[4:0],1'b0}; endfunction
    function automatic [5:0] p1(input [5:0] s); p1={s[4:0],1'b1}; endfunction
    /* verilator lint_on UNUSED */
    function automatic crc16_check;
      integer k,j; reg [47:0] w; reg [16:0] poly;
      begin
        for(k=0;k<48;k=k+1) w[47-k]=decoded[k]; poly={1'b1,16'h1021};
        for(k=0;k<32;k=k+1) if(w[47-k]) for(j=0;j<=16;j=j+1) if(poly[16-j]) w[47-k-j]=~w[47-k-j];
        crc16_check=1'b1; for(k=0;k<16;k=k+1) if(w[k]) crc16_check=1'b0;
      end
    endfunction
    wire signed [LLR_W-1:0] a0=llr_mem[{step,1'b0}],a1=llr_mem[{step,1'b1}];
    wire [5:0] pred0=p0(acs_dest),pred1=p1(acs_dest);
    wire signed [METRIC_W-1:0] cand0=(metric[pred0]==NEG)?NEG:metric[pred0]+bm(conv_out(pred0,acs_dest[5]),a0,a1);
    wire signed [METRIC_W-1:0] cand1=(metric[pred1]==NEG)?NEG:metric[pred1]+bm(conv_out(pred1,acs_dest[5]),a0,a1);
    wire [11:0] dlen={decoded[8],decoded[9],decoded[10],decoded[11],decoded[12],decoded[13],decoded[14],decoded[15],decoded[16],decoded[17],decoded[18],decoded[19]};
    wire [6:0] dseed={decoded[20],decoded[21],decoded[22],decoded[23],decoded[24],decoded[25],decoded[26]};
    wire [1:0] dmid={decoded[27],decoded[28]};
    assign in_ready=(state==COLLECT);
    always @(posedge clk) begin
      if(rst) begin
        state<=IDLE;in_count<=0;step<=0;acs_dest<=0;acs_eval<=0;dest_q<=0;cand0_q<=0;cand1_q<=0;trace_step<=0;trace_state<=0;decoded<=0;
        header_valid<=0;header_ok<=0;payload_bytes<=0;scrambler_seed<=0;midamble_code<=0;crc_ok<=0;header_error<=0;busy<=0;
        for(i=0;i<64;i=i+1) metric[i]<=(i==0)?'0:NEG;
      end else begin
        header_valid<=0;header_error<=0;
        if(start && state==IDLE) begin state<=COLLECT;in_count<=0;busy<=1;end
        if(state==COLLECT && in_valid && in_ready) begin
          if(in_count<108) llr_mem[in_count[6:0]]<=in_llr;
          if(in_last) begin if(in_count!=191) begin state<=IDLE;busy<=0;header_error<=1;end else begin state<=ACS;step<=0;acs_dest<=0;for(i=0;i<64;i=i+1) metric[i]<=(i==0)?'0:NEG;end end
          else if(in_count==191) begin state<=IDLE;busy<=0;header_error<=1;end else in_count<=in_count+1'b1;
        end
        if(state==ACS) begin
          if(!acs_eval) begin
            cand0_q<=cand0; cand1_q<=cand1; dest_q<=acs_dest; acs_eval<=1'b1;
          end else begin
          if(cand1_q>cand0_q) begin metric_new[dest_q]<=cand1_q; survivor_mem[dest_q][step]<=1'b1; end
          else begin metric_new[dest_q]<=cand0_q; survivor_mem[dest_q][step]<=1'b0; end
          if(dest_q==63) begin
            for(i=0;i<63;i=i+1) metric[i]<=metric_new[i];
            if(cand1_q>cand0_q) metric[63]<=cand1_q; else metric[63]<=cand0_q;
            acs_dest<=0; acs_eval<=1'b0;
            if(step==53) begin state<=TRACE;trace_step<=53;trace_state<=0;end else step<=step+1'b1;
          end else begin acs_dest<=acs_dest+1'b1; acs_eval<=1'b0; end
          end
        end
        if(state==TRACE) begin decoded[trace_step]<=trace_state[5]; trace_state<=survivor_mem[trace_state][trace_step]?p1(trace_state):p0(trace_state); if(trace_step==0) state<=VALIDATE; else trace_step<=trace_step-1'b1; end
        if(state==VALIDATE) begin
          crc_ok<=crc16_check(); header_valid<=1;busy<=0;payload_bytes<=dlen;scrambler_seed<=dseed;midamble_code<=dmid;
          header_ok<=crc16_check() && ({decoded[0],decoded[1],decoded[2],decoded[3]}==4'b0010) && ({decoded[4],decoded[5],decoded[6],decoded[7]}==4'b0000) && dlen>0 && dlen<=12'(MAX_PAYLOAD) && dseed!=0 && dmid<=2 && !(|decoded[53:48]);
          state<=IDLE;
        end
      end
    end
endmodule
