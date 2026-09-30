`timescale 1ns/1ps
// Scalar layered NMS, exactly the quantizedDecoder arithmetic in MATLAB:
// input/messages Q2 +/-63 (7 bits), extrinsic/post Q2 +/-255 (9 bits),
// alpha=3/4, nearest rounding with ties away from zero. All large RAM reads
// are synchronous. First iteration ignores old messages: no clear/epoch RAM.
// Correctness/resource baseline; this scalar core is NOT an air-rate core.
module cofdm_qcldpc_648_decoder #(parameter integer MAX_ITERS=12)(
    input wire clk,rst,start,in_valid,in_last,
    output wire in_ready,
    input wire signed [6:0] in_llr,
    output reg out_valid, input wire out_ready,
    output reg out_last,out_bit,done,decode_ok,syndrome_ok,
    output reg [4:0] iterations_done,
    output reg frame_error, output wire busy
);
    localparam [3:0] IDLE=0,LOAD=1,ROM=2,MEM=3,QCALC=4,QMIN=5,UCALC=6,WRITE=7,
        CROM=8,CMEM=9,PARITY=10,DECIDE=11,OREQ=12,OHOLD=13;
    reg [3:0] state;
    reg [9:0] load_idx,out_idx;
    reg [8:0] check_idx;
    reg [2:0] slot,last_slot,min_slot;
    reg [4:0] iter;
    reg [8:0] min1,min2;
    reg signs,parity,bad_checks;
    wire [11:0] edge_addr={check_idx,slot};
    wire [10:0] edge_word;
    cofdm_qcldpc_edge_rom rom(.clk,.addr(edge_addr),.data(edge_word));
    (* ram_style="block" *) reg signed [8:0] post_mem[0:647];
    (* ram_style="block" *) reg signed [6:0] msg_mem[0:2591];
    reg signed [8:0] post_rd;
    reg signed [6:0] msg_rd;
    reg signed [8:0] q_cache[0:7];
    reg [9:0] addr_cache[0:7];
    reg signed [8:0] post_new;
    reg signed [6:0] msg_new;
    wire signed [9:0] diff=$signed({post_rd[8],post_rd})-
        ((iter==0)?10'sd0:$signed({{3{msg_rd[6]}},msg_rd}));
    function automatic signed [8:0] sat9(input signed [9:0] x);
        if(x>10'sd255) sat9=9'sd255;
        else if(x< -10'sd255) sat9=-9'sd255;
        else sat9=x[8:0];
    endfunction
    wire signed [8:0] q=sat9(diff);
    wire [8:0] selected=(slot==min_slot)?min2:min1;
    wire marker = edge_word[10];
    function automatic [7:0] scale_min(input [8:0] x);
      scale_min=8'((({2'b0,x}<<1)+{2'b0,x}+11'd2)>>2);
    endfunction
    wire [7:0] scaled=scale_min(selected);
    wire [5:0] clipped=(scaled>8'd63)?6'd63:scaled[5:0];
    wire signed [6:0] rnew=(signs^q_cache[slot][8])?-$signed({1'b0,clipped}):$signed({1'b0,clipped});
    wire signed [9:0] sum=$signed({q_cache[slot][8],q_cache[slot]})+$signed({{3{rnew[6]}},rnew});
    wire [8:0] cached_mag=q_cache[slot][8]?$unsigned(-q_cache[slot]):$unsigned(q_cache[slot]);
    // Mux addresses before the memory statement: one read/write port each.
    wire load_write=state==LOAD && in_valid;
    wire post_we=!rst && (load_write || state==WRITE);
    wire [9:0] post_wa=load_write?load_idx:addr_cache[slot];
    wire signed [8:0] post_wd=load_write?
        ((in_llr== -7'sd64)? -9'sd63:$signed({{2{in_llr[6]}},in_llr})):post_new;
    wire [9:0] post_ra=(state==OREQ)?out_idx:edge_word[9:0];
    always @(posedge clk) begin
        if(post_we) post_mem[post_wa]<=post_wd;
        if(state==MEM || state==CMEM || state==OREQ) post_rd<=post_mem[post_ra];
        if(!rst && state==WRITE) msg_mem[edge_addr]<=msg_new;
        if(state==MEM) msg_rd<=msg_mem[edge_addr];
    end
    assign busy=(state!=IDLE);
    assign in_ready=(state==LOAD) && !rst;
    initial if(MAX_ITERS<1 || MAX_ITERS>31) $error("MAX_ITERS must be 1..31");
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;load_idx<=0;out_idx<=0;check_idx<=0;slot<=0;last_slot<=0;
            min_slot<=0;iter<=0;min1<=511;min2<=511;signs<=0;parity<=0;bad_checks<=0;
            out_valid<=0;out_last<=0;out_bit<=0;done<=0;decode_ok<=0;syndrome_ok<=0;
            iterations_done<=0;frame_error<=0;post_new<=0;msg_new<=0;
        end else begin
            done<=0;frame_error<=0;
            case(state)
            IDLE: if(start) begin
                state<=LOAD;load_idx<=0;decode_ok<=0;syndrome_ok<=0;iterations_done<=0;
            end
            LOAD: if(in_valid) begin
                if(in_last!=(load_idx==647)) begin frame_error<=1;state<=IDLE;end
                else if(load_idx==647) begin
                    check_idx<=0;slot<=0;iter<=0;min1<=511;min2<=511;signs<=0;state<=ROM;
                end else load_idx<=load_idx+1'b1;
            end
            ROM: state<=MEM;
            MEM: state<=QCALC;
            QCALC: begin
                q_cache[slot]<=q;addr_cache[slot]<=edge_word[9:0];state<=QMIN;
            end
            QMIN: begin
                signs<=signs^q_cache[slot][8];
                if(cached_mag<min1) begin min2<=min1;min1<=cached_mag;min_slot<=slot;end
                else if(cached_mag<min2) min2<=cached_mag;
                if(marker) begin last_slot<=slot;slot<=0;state<=UCALC;end
                else begin slot<=slot+1'b1;state<=ROM;end
            end
            UCALC: begin post_new<=sat9(sum);msg_new<=rnew;state<=WRITE;end
            WRITE: begin
                if(slot!=last_slot) begin slot<=slot+1'b1;state<=UCALC;end
                else begin
                    slot<=0;min1<=511;min2<=511;signs<=0;
                    if(check_idx==323) begin
                        check_idx<=0;parity<=0;bad_checks<=0;state<=CROM;
                        iterations_done<=iter+1'b1;
                    end else begin check_idx<=check_idx+1'b1;state<=ROM;end
                end
            end
            CROM: state<=CMEM;
            CMEM: state<=PARITY;
            PARITY: begin
                if(marker) begin
                    bad_checks<=bad_checks|(parity^post_rd[8]);parity<=0;slot<=0;
                    if(check_idx==323) state<=DECIDE;
                    else begin check_idx<=check_idx+1'b1;state<=CROM;end
                end else begin parity<=parity^post_rd[8];slot<=slot+1'b1;state<=CROM;end
            end
            DECIDE: begin
                if(!bad_checks || iter==5'(MAX_ITERS-1)) begin
                    decode_ok<=!bad_checks;syndrome_ok<=!bad_checks;out_idx<=0;state<=OREQ;
                end else begin iter<=iter+1'b1;check_idx<=0;slot<=0;state<=ROM;end
            end
            OREQ: state<=OHOLD;
            OHOLD: begin
                if(!out_valid) begin out_valid<=1;out_bit<=post_rd[8];out_last<=out_idx==323;end
                else if(out_ready) begin
                    out_valid<=0;out_last<=0;
                    if(out_idx==323) begin done<=1;state<=IDLE;end
                    else begin out_idx<=out_idx+1'b1;state<=OREQ;end
                end
            end
            default:state<=IDLE;
            endcase
        end
    end
endmodule
