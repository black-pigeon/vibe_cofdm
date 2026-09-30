`timescale 1ns/1ps
// Exact integer STF statistic from synchronize.m. Accepted-sample indexing.
// E1/E2 are squared energies, P=sum(conj(old)*new), threshold NUM/DEN.
// Streaming energy floor replaces MATLAB's noncausal 0.1*max(E1) gate.
// No reset on RAM arrays: fill counters mask stale data after reset.
module cofdm_stf_sync_frontend #(
    parameter integer IW=16, L=16, W=64, ACC_W=40,
    parameter integer METRIC_NUM=40, METRIC_DEN=100, SYNC_MIN_RUN=24,
    parameter integer PTR_W=(W<=2)?1:$clog2(W),
    parameter integer DLY_W=(L<=2)?1:$clog2(L),
    parameter [ACC_W-1:0] MIN_ENERGY=1
)(
    input wire clk, rst, sample_valid,
    input wire signed [IW-1:0] sample_re, sample_im,
    output reg metric_valid, sync_hit,
    output reg [31:0] sync_index,
    output reg signed [ACC_W-1:0] corr_re, corr_im,
    output reg [ACC_W-1:0] energy_old, energy_new
);
    localparam TW=2*IW+1;
    localparam CW=2*ACC_W+1+$clog2((METRIC_DEN>METRIC_NUM)?METRIC_DEN+1:METRIC_NUM+1);
    localparam RW=(SYNC_MIN_RUN<2)?1:$clog2(SYNC_MIN_RUN+1);
    (* ram_style="distributed" *) reg [2*IW-1:0] delay_mem[0:L-1];
    reg [DLY_W-1:0] dp;
    reg [DLY_W:0] filled;
    reg [31:0] sample_index;
    wire signed [IW-1:0] dr=delay_mem[dp][IW-1:0];
    wire signed [IW-1:0] di=delay_mem[dp][2*IW-1:IW];
    reg signed [IW-1:0] ar,ai,br,bi;
    reg v0,v1,v2,v3,v4,v5,v6,v7;
    reg [31:0] n0,n1,n2,n3,n4,n5,n6,n7;
    reg signed [2*IW-1:0] rr,ii,ri,ir;
    reg [2*IW-1:0] aa,ab,ba,bb;
    reg signed [TW-1:0] tr,ti;
    reg [TW-1:0] te,tf;
    (* ram_style="distributed" *) reg [4*TW-1:0] history[0:W-1];
    reg [PTR_W-1:0] wp;
    reg [PTR_W:0] wf;
    wire signed [TW-1:0] hr=history[wp][TW-1:0];
    wire signed [TW-1:0] hi=history[wp][2*TW-1:TW];
    wire [TW-1:0] he=history[wp][3*TW-1:2*TW];
    wire [TW-1:0] hf=history[wp][4*TW-1:3*TW];
    reg signed [TW:0] delta_r,delta_i,delta_e,delta_f;
    reg full3;
    reg signed [ACC_W-1:0] sr,si;
    reg [ACC_W-1:0] se,sf;
    reg [2*ACC_W-1:0] r2,i2,ef;
    reg [2*ACC_W:0] mag6;
    reg [2*ACC_W-1:0] ef6;
    reg [CW-1:0] lhs7,rhs7;
    reg [RW-1:0] run_count;
    reg latched;
    // Align diagnostic P/E to the gate, including bubbles.
    reg [4*ACC_W-1:0] meta5,meta6,meta7;
    wire gate=(lhs7>rhs7) && (meta7[3*ACC_W-1:2*ACC_W]>=MIN_ENERGY)
                              && (meta7[4*ACC_W-1:3*ACC_W]>=MIN_ENERGY);
    always @(posedge clk) begin
        if (!rst && sample_valid) delay_mem[dp]<={sample_im,sample_re};
        if (!rst && v2) history[wp]<={tf,te,ti,tr};
        if(rst) begin
            dp<=0;filled<=0;sample_index<=0;wp<=0;wf<=0;
            v0<=0;v1<=0;v2<=0;v3<=0;v4<=0;v5<=0;v6<=0;v7<=0;
            sr<=0;si<=0;se<=0;sf<=0;full3<=0;
            run_count<=0;latched<=0;metric_valid<=0;sync_hit<=0;
            sync_index<=0;corr_re<=0;corr_im<=0;energy_old<=0;energy_new<=0;
        end else begin
            v0<=sample_valid && (filled== (DLY_W+1)'(L));
            if(sample_valid) begin
                ar<=dr;ai<=di;br<=sample_re;bi<=sample_im;n0<=sample_index;
                sample_index<=sample_index+1'b1;
                if(filled<(DLY_W+1)'(L)) filled<=filled+1'b1;
                dp<=(dp==DLY_W'(L-1)) ? '0 : dp+1'b1;
            end
            v1<=v0;
            if(v0) begin
                rr<=ar*br;ii<=ai*bi;ri<=ar*bi;ir<=ai*br;
                aa<=ar*ar;ab<=ai*ai;ba<=br*br;bb<=bi*bi;n1<=n0;
            end
            v2<=v1;
            if(v1) begin
                tr<=$signed({rr[2*IW-1],rr})+$signed({ii[2*IW-1],ii});
                ti<=$signed({ri[2*IW-1],ri})-$signed({ir[2*IW-1],ir});
                te<={1'b0,aa}+{1'b0,ab};tf<={1'b0,ba}+{1'b0,bb};n2<=n1;
            end
            v3<=v2;
            if(v2) begin
                delta_r<=$signed({tr[TW-1],tr})-((wf==(PTR_W+1)'(W))?$signed({hr[TW-1],hr}):$signed({(TW+1){1'b0}}));
                delta_i<=$signed({ti[TW-1],ti})-((wf==(PTR_W+1)'(W))?$signed({hi[TW-1],hi}):$signed({(TW+1){1'b0}}));
                delta_e<=$signed({1'b0,te})-((wf==(PTR_W+1)'(W))?$signed({1'b0,he}):$signed({(TW+1){1'b0}}));
                delta_f<=$signed({1'b0,tf})-((wf==(PTR_W+1)'(W))?$signed({1'b0,hf}):$signed({(TW+1){1'b0}}));
                full3<=wf>=(PTR_W+1)'(W-1);n3<=n2;
                if(wf<(PTR_W+1)'(W)) wf<=wf+1'b1;
                wp<=(wp==PTR_W'(W-1))?'0:wp+1'b1;
            end
            v4<=v3 && full3;
            if(v3) begin
                sr<=sr+ACC_W'(delta_r);si<=si+ACC_W'(delta_i);
                se<=se+ACC_W'(delta_e);sf<=sf+ACC_W'(delta_f);n4<=n3;
            end
            v5<=v4;
            if(v4) begin
                r2<=sr*sr;i2<=si*si;ef<=se*sf;
                meta5<={sf,se,si,sr};n5<=n4;
            end
            v6<=v5;
            if(v5) begin
                mag6<={1'b0,r2}+{1'b0,i2};ef6<=ef;meta6<=meta5;n6<=n5;
            end
            v7<=v6;
            if(v6) begin
                lhs7<=CW'(mag6)*CW'(METRIC_DEN);rhs7<=CW'(ef6)*CW'(METRIC_NUM);
                meta7<=meta6;n7<=n6;
            end
            metric_valid<=v7;sync_hit<=0;
            if(v7) begin
                {energy_new,energy_old,corr_im,corr_re}<=meta7;
                if(gate) begin
                    if(run_count<RW'(SYNC_MIN_RUN))run_count<=run_count+1'b1;
                    if(run_count==RW'(SYNC_MIN_RUN-1) && !latched)begin
                        sync_hit<=1;sync_index<=n7;latched<=1;
                    end
                end else begin run_count<=0;latched<=0;end
            end
        end
    end
endmodule
