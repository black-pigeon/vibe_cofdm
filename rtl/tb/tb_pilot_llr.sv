`timescale 1ns/1ps
module tb_pilot_llr;
  reg clk=0,rst=1; always #5 clk=~clk;
  reg pv=0,plast=0,ps=0; reg signed [15:0] yr=0,yi=0; reg signed [17:0] hr=0,hi=0;
  wire pr,phase_iv,phase_v,busy; wire signed [47:0] sr,si; wire signed [31:0] phase;
  wire [7:0] pc;
  cofdm_pilot_phase_accum p(.clk,.rst,.pilot_valid(pv),.pilot_last(plast),.pilot_sign(ps),
    .y_re(yr),.y_im(yi),.h_re(hr),.h_im(hi),.pilot_ready(pr),.phase_in_valid(phase_iv),
    .phase_sum_re(sr),.phase_sum_im(si),.phase_valid(phase_v),
    .phase,.phase_busy(busy),.pilot_count(pc));
  reg lv=0,mode=0; reg signed [15:0] ly_r=0,ly_i=0; reg signed [17:0] lh_r=0,lh_i=0; reg [23:0] inv=0;
  wire lov,lol; wire signed [15:0] lr,li; wire ls;
  cofdm_matched_llr l(.clk,.rst,.in_valid(lv),.mode_bpsk(mode),.y_re(ly_r),.y_im(ly_i),
    .h_re(lh_r),.h_im(lh_i),.inv_noise_q16(inv),.in_ready(),.out_valid(lov),.out_last(lol),
    .llr_re(lr),.llr_im(li),.saturated(ls));
  integer k; real pi=3.141592653589793; integer errs=0; reg saw_phase=0; reg signed [31:0] phase_seen=0;
  always @(posedge clk) if (phase_v) begin saw_phase=1; phase_seen=phase; end
  task pilot(input integer sgn,input integer la); begin @(negedge clk); pv=1; ps=sgn; plast=la; yr=16'sd8192; yi=0; hr=18'sd16384; hi=0; @(posedge clk); #1 pv=0; plast=0; end endtask
  initial begin
    #12 rst=0; for(k=0;k<8;k=k+1) pilot(0,k==7); repeat(20) @(posedge clk);
    if(!saw_phase || phase_seen>32'sd1000000 || phase_seen< -32'sd1000000) begin $display("FAIL pilot valid=%0d phase=%0d",saw_phase,phase_seen); errs=errs+1; end
    @(negedge clk); mode=0; lv=1; ly_r=16'sd8192; ly_i=16'sd4096; lh_r=18'sd16384; lh_i=0; inv=24'd65536;
    @(posedge clk); #1 lv=0; wait(lov===1'b1); #1; if(lr<=0 || li<=0 || !lol) begin $display("FAIL QPSK llr %0d %0d",lr,li); errs=errs+1; end
    @(negedge clk); mode=1; lv=1; ly_r=-16'sd8192; ly_i=0; @(posedge clk); #1 lv=0;
    wait(lov===1'b1); #1; if(lr>=0 || !lol) begin $display("FAIL BPSK llr %0d",lr); errs=errs+1; end
    if(errs) $fatal(1,"pilot/LLR errors=%0d",errs); $display("PASS pilot phase and matched LLR"); $finish;
  end
endmodule
