`timescale 1ns/1ps
module tb_cfo_angle_estimator;
    reg clk=0,rst=1,start=0; reg signed [39:0] re=0,im=0;
    wire busy,valid; wire signed [31:0] angle,inc;
    cofdm_cfo_angle_estimator dut(.clk,.rst,.start,.corr_re(re),.corr_im(im),
      .busy,.valid,.angle_turns(angle),.phase_inc(inc));
    always #5 clk=~clk;
    initial begin
      #12 rst=0; re=10000; im=10000;
      @(negedge clk); start=1; @(negedge clk); start=0;
      wait(valid); #1;
      // atan2(1,1)=1/8 turn, correction is -1/8/16=-1/128 turn/sample.
      if (angle < 32'sd530000000 || angle > 32'sd545000000)
        $fatal(1,"angle %0d",angle);
      if (inc > -32'sd32000000 || inc < -32'sd35000000)
        $fatal(1,"phase inc %0d",inc);
      $display("PASS CFO angle angle=%0d phase_inc=%0d",angle,inc);
      $finish;
    end
endmodule
