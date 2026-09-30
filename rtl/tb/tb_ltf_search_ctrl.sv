`timescale 1ns/1ps
module tb_ltf_search_ctrl;
    reg clk=0,rst=1,v=0,hit=0,done=0; reg [31:0] idx=0; wire start,pending,error; wire [31:0] base;
    cofdm_ltf_search_ctrl #(.STF_TO_LTF_USEFUL(12),.SEARCH_RADIUS(2),.TIMER_W(5)) dut(
      .clk,.rst,.sample_valid(v),.stf_hit(hit),.stf_index(idx),.search_done(done),.search_start(start),
      .search_base_index(base),.search_pending(pending),.search_error(error));
    always #5 clk=~clk;
    integer k, starts; reg seen=0;
    task tick(input h,input [31:0] i);
      begin @(negedge clk);v=1;hit=h;idx=i;@(posedge clk);#1;v=0;hit=0;end
    endtask
    always @(posedge clk) if(start) begin seen=1; starts=starts+1;
      if ((starts==1 && base!==110) || (starts==2 && base!==210))
        $fatal(1,"start=%0d base=%0d",starts,base); end
    initial begin #12 rst=0; starts=0; tick(1,100); for(k=0;k<12;k=k+1) tick(0,0);
      // A completed matcher transaction must release the guard for the next
      // frame without resetting the scheduler.
      @(negedge clk); v=1; done=1; @(posedge clk); #1; v=0; done=0;
      tick(1,200); for(k=0;k<12;k=k+1) tick(0,0);
      if(!seen || starts!=2 || error) $fatal(1,"search ctrl seen=%0d starts=%0d err=%0d",seen,starts,error);
      $display("PASS LTF search controller");$finish; end
endmodule
