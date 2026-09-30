`timescale 1ns/1ps
module tb_cfo_control;
    reg clk=0,rst=1,candidate=0,cv=0,fv=0; reg signed [31:0] ci=0,fi=0;
    wire signed [31:0] inc; wire clear,cl,fl;
    cofdm_cfo_control dut(.clk,.rst,.candidate_pulse(candidate),.coarse_valid(cv),
      .coarse_inc(ci),.fine_valid(fv),.fine_inc(fi),.phase_inc(inc),.clear_phase(clear),
      .coarse_locked(cl),.fine_locked(fl));
    always #5 clk=~clk;
    task tick(input c,input cvalid,input fvalid,input signed [31:0] cword,input signed [31:0] fword);
      begin @(negedge clk); candidate=c;cv=cvalid;fv=fvalid;ci=cword;fi=fword;@(posedge clk);#1;
        candidate=0;cv=0;fv=0; end
    endtask
    initial begin
      #12 rst=0;
      tick(1,0,0,0,0); if(!clear || inc!==0) $fatal(1,"candidate control");
      tick(0,1,0,32'sd100,0); if(inc!==100 || !cl) $fatal(1,"coarse control");
      tick(0,0,1,0,-32'sd7); if(inc!==93 || !fl) $fatal(1,"fine control inc=%0d",inc);
      $display("PASS CFO control inc=%0d",inc);$finish;
    end
endmodule
