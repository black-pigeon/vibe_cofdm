`timescale 1ns/1ps
module tb_sync_frontend_auto_top;
    reg clk=0,rst=1,valid=0; reg signed [15:0] re=0,im=0; reg fine=0; reg signed [31:0] fi=0;
    wire mv,hit,cv,rv,clear,cl,fl; wire [31:0] idx,dbg; wire signed [15:0] rr,ri; wire signed [31:0] ci,inc;
    cofdm_sync_frontend_auto_top dut(.clk,.rst,.sample_valid(valid),.sample_re(re),.sample_im(im),
      .fine_valid(fine),.fine_phase_inc(fi),.metric_valid(mv),.sync_hit(hit),.sync_index(idx),
      .corrected_valid(rv),.corrected_re(rr),.corrected_im(ri),.phase_dbg(dbg),.coarse_valid(cv),
      .coarse_phase_inc(ci),.phase_inc(inc),.clear_phase(clear),.coarse_locked(cl),.fine_locked(fl));
    always #5 clk=~clk;
    integer k; reg saw_hit=0,saw_coarse=0;
    task send(input signed [15:0] x,input signed [15:0] y);
      begin @(negedge clk);valid=1;re=x;im=y;@(posedge clk);#1;valid=0;end
    endtask
    always @(posedge clk) begin if(hit)saw_hit=1; if(cv)saw_coarse=1; end
    initial begin
      #12 rst=0;
      // Repeated complex tone produces a strong STF correlation and a zero CFO.
      for(k=0;k<180;k=k+1) send((k%16==0)?16'sd1000:16'sd0,0);
      repeat(30) @(posedge clk);
      if(!saw_hit || !saw_coarse || !cl) $fatal(1,"auto sync hit=%0d coarse=%0d locked=%0d",saw_hit,saw_coarse,cl);
      @(negedge clk); fine=1;fi=-32'sd7;@(posedge clk);#1;fine=0;
      if(inc !== ci-32'sd7 || !fl) $fatal(1,"fine update inc=%0d coarse=%0d",inc,ci);
      $display("PASS automatic sync/CFO top inc=%0d",inc);$finish;
    end
endmodule
