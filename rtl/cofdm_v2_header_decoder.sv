`timescale 1ns/1ps
// Soft-decision K=7, rate-1/2 Viterbi decoder for the COFDM v2 PHY header.
//
// The packetizer has already removed the 31-seed Header PRBS.  This block
// consumes 192 BPSK LLRs (108 coded bits followed by 84 ignored pad bits),
// decodes the first 54 trellis steps, traces back to known state zero, checks
// CRC16 and validates the v2 fields.  One 64-state ACS update is performed
// per clock.  The survivor matrix is 54*64 bits and maps to BRAM/LUTRAM;
// there is no multiplier or divider in the decoder.
module cofdm_v2_header_decoder #(
    parameter integer LLR_W=16,
    parameter integer METRIC_W=26,
    parameter integer MAX_PAYLOAD=2048
) (
    input wire clk,input wire rst,input wire start,
    input wire in_valid,input wire in_last,
    output wire in_ready,input wire signed [LLR_W-1:0] in_llr,
    output reg header_valid,output reg header_ok,
    output reg [11:0] payload_bytes,output reg [6:0] scrambler_seed,
    output reg [1:0] midamble_code,output reg crc_ok,
    output reg header_error,output reg busy
);
    localparam [2:0] S_IDLE=3'd0,S_COLLECT=3'd1,S_ACS=3'd2,
                     S_TRACE=3'd3,S_VALIDATE=3'd4;
    localparam signed [METRIC_W-1:0] NEG_METRIC={1'b1,{(METRIC_W-1){1'b0}}};
    reg [2:0] state;
    reg [7:0] in_count;
    reg [5:0] step,trace_step,trace_state;
    reg signed [LLR_W-1:0] llr_mem[0:107];
    reg signed [METRIC_W-1:0] metric[0:63];
    reg survivor[0:53][0:63];
    reg [53:0] decoded;
    reg signed [METRIC_W-1:0] metric_next[0:63];
    reg survivor_next[0:63];
    integer i;

    function automatic [1:0] conv_out(input [5:0] prev,input bit u);
        reg [6:0] r;
        begin
            r={u,prev};
            conv_out[1]=^(r & 7'b1011011); // octal 133
            conv_out[0]=^(r & 7'b1111001); // octal 171
        end
    endfunction
    function automatic signed [METRIC_W-1:0] branch_metric(
        input [1:0] bits,input signed [LLR_W-1:0] l0,input signed [LLR_W-1:0] l1);
        reg signed [METRIC_W-1:0] a,b;
        begin
            a={{(METRIC_W-LLR_W){l0[LLR_W-1]}},l0};
            b={{(METRIC_W-LLR_W){l1[LLR_W-1]}},l1};
            if(bits[0]) a=-a;
            if(bits[1]) b=-b;
            branch_metric=a+b;
        end
    endfunction
    /* verilator lint_off UNUSED */
    function automatic [5:0] prev0(input [5:0] next_s);
        prev0={next_s[4:0],1'b0};
    endfunction
    function automatic [5:0] prev1(input [5:0] next_s);
        prev1={next_s[4:0],1'b1};
    endfunction
    /* verilator lint_on UNUSED */
    wire signed [LLR_W-1:0] llr0=llr_mem[{step,1'b0}];
    wire signed [LLR_W-1:0] llr1=llr_mem[{step,1'b1}];
    always @* begin
        for(i=0;i<64;i=i+1) begin
            reg [5:0] p0,p1;
            reg signed [METRIC_W-1:0] a,b;
            p0=prev0(i[5:0]); p1=prev1(i[5:0]);
            if(metric[p0]==NEG_METRIC) a=NEG_METRIC;
            else a=metric[p0]+branch_metric(conv_out(p0,i[5]),llr0,llr1);
            if(metric[p1]==NEG_METRIC) b=NEG_METRIC;
            else b=metric[p1]+branch_metric(conv_out(p1,i[5]),llr0,llr1);
            if(a>=b) begin metric_next[i]=a; survivor_next[i]=1'b0; end
            else begin metric_next[i]=b; survivor_next[i]=1'b1; end
        end
    end
    function automatic crc16_check;
        integer k,j; reg [47:0] work; reg [16:0] poly_bits;
        begin
            for(k=0;k<48;k=k+1) work[47-k]=decoded[k];
            poly_bits={1'b1,16'h1021};
            for(k=0;k<32;k=k+1) if(work[47-k]) begin
                for(j=0;j<=16;j=j+1) if(poly_bits[16-j])
                    work[47-k-j]=~work[47-k-j];
            end
            crc16_check=1'b1;
            for(k=0;k<16;k=k+1) if(work[k]) crc16_check=1'b0;
        end
    endfunction
    assign in_ready=(state==S_COLLECT);
    wire [11:0] decoded_payload={decoded[8],decoded[9],decoded[10],decoded[11],decoded[12],decoded[13],decoded[14],decoded[15],decoded[16],decoded[17],decoded[18],decoded[19]};
    wire [6:0] decoded_seed={decoded[20],decoded[21],decoded[22],decoded[23],decoded[24],decoded[25],decoded[26]};
    wire [1:0] decoded_mid={decoded[27],decoded[28]};

    always @(posedge clk) begin
        if(rst) begin
            state<=S_IDLE; in_count<=0; step<=0; trace_step<=0; trace_state<=0;
            header_valid<=0; header_ok<=0; payload_bytes<=0; scrambler_seed<=0;
            midamble_code<=0; crc_ok<=0; header_error<=0; busy<=0;
            for(i=0;i<64;i=i+1) metric[i]<=(i==0)?'0:NEG_METRIC;
        end else begin
            header_valid<=0; header_error<=0;
            if(start && state==S_IDLE) begin
                state<=S_COLLECT; in_count<=0; busy<=1; crc_ok<=0;
            end
            if(state==S_COLLECT && in_valid && in_ready) begin
                if(in_count<108) llr_mem[in_count[6:0]]<=in_llr;
                if(in_last) begin
                    if(in_count!=191) begin state<=S_IDLE; busy<=0; header_error<=1; end
                    else begin state<=S_ACS; step<=0; for(i=0;i<64;i=i+1) metric[i]<=(i==0)?'0:NEG_METRIC; end
                end else if(in_count==191) begin state<=S_IDLE; busy<=0; header_error<=1; end
                else in_count<=in_count+1'b1;
            end
            if(state==S_ACS) begin
                for(i=0;i<64;i=i+1) begin metric[i]<=metric_next[i]; survivor[step][i]<=survivor_next[i]; end
                if(step==53) begin state<=S_TRACE; trace_step<=53; trace_state<=0; end
                else step<=step+1'b1;
            end
            if(state==S_TRACE) begin
                decoded[trace_step]<=trace_state[5];
                trace_state<=survivor[trace_step][trace_state] ? prev1(trace_state) : prev0(trace_state);
                if(trace_step==0) state<=S_VALIDATE;
                else trace_step<=trace_step-1'b1;
            end
            if(state==S_VALIDATE) begin
                crc_ok<=crc16_check();
                header_valid<=1; busy<=0;
                payload_bytes<=decoded_payload;
                scrambler_seed<=decoded_seed;
                midamble_code<=decoded_mid;
                header_ok<=crc16_check() && ({decoded[0],decoded[1],decoded[2],decoded[3]}==4'b0010) &&
                    ({decoded[4],decoded[5],decoded[6],decoded[7]}==4'b0000) &&
                    (decoded_payload>0) && (decoded_payload<=12'(MAX_PAYLOAD)) &&
                    (decoded_seed!=0) && (decoded_mid<=2) &&
                    !decoded[29] && !decoded[30] && !decoded[31] &&
                    !(|decoded[53:48]);
                state<=S_IDLE;
            end
        end
    end
endmodule
