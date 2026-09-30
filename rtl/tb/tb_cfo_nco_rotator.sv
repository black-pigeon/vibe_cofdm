`timescale 1ns/1ps
module tb_cfo_nco_rotator;
    reg clk=0,rst=1,clear=0,valid=0;
    reg signed [31:0] inc=0;
    reg signed [15:0] ir=0, ii=0;
    wire ov; wire signed [15:0] orr,oi; wire [31:0] ph;
    cofdm_cfo_nco_rotator dut(.clk,.rst,.clear_phase(clear),.sample_valid(valid),
      .phase_inc(inc),.in_re(ir),.in_im(ii),.out_valid(ov),.out_re(orr),.out_im(oi),.phase_dbg(ph));
    always #5 clk=~clk;
    integer n;
    initial begin
      #12 rst=0; ir=10000; ii=0; inc=0;
      for(n=0;n<4;n=n+1) begin @(negedge clk); valid=1; end
      @(negedge clk); valid=0;
      if (orr < 9900 || orr > 10000 || oi !== 0) $fatal(1,"identity %0d %0d",orr,oi);
      // A quarter-turn increment should rotate a real input close to
      // (cos,sin) = (0,1) on the second accepted sample.
      @(negedge clk); inc=32'h40000000; valid=1;
      @(negedge clk); valid=1;
      @(negedge clk); valid=0;
      repeat(3) @(posedge clk); #1;
      if (oi < 9800 || orr > 300) $fatal(1,"quarter turn %0d %0d",orr,oi);
      $display("PASS CFO NCO rotator identity=%0d quarter=%0d+j%0d",10000,orr,oi);
      $finish;
    end
endmodule
