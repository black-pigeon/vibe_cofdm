`timescale 1ns/1ps
module tb_cordic_atan2;
    reg clk=0, rst=1, valid=0;
    reg signed [63:0] re=0, im=0;
    wire ready, out_valid, busy;
    wire signed [31:0] phase;
    cofdm_cordic_atan2 dut(.clk,.rst,.in_valid(valid),.in_ready(ready),
      .in_re(re),.in_im(im),.out_valid,.out_phase(phase),.busy);
    always #5 clk=~clk;
    task automatic run_case(input signed [63:0] xr, input signed [63:0] xi,
                             input signed [31:0] expected, input [31:0] tol);
      reg signed [31:0] err;
      begin
        @(negedge clk); while(!ready) @(negedge clk);
        re=xr; im=xi; valid=1; @(posedge clk); #1 valid=0;
        wait(out_valid); err=phase-expected;
        if (err < 0) err=-err;
        if (err > tol) $fatal(1,"atan2 (%0d,%0d) phase=%0d expected=%0d",xr,xi,phase,expected);
      end
    endtask
    initial begin
      #12 rst=0;
      run_case(64'sd1000000,64'sd0,32'sd0,32'd30000);
      run_case(64'sd0,64'sd1000000,32'sh3243f6a9,32'd30000);
      run_case(-64'sd1000000,64'sd0,32'sh6487ed51,32'd30000);
      run_case(64'sd0,-64'sd1000000,-32'sh3243f6a9,32'd30000);
      run_case(-64'sd1000000,-64'sd1000000,-32'sh4b65f1fd,32'd30000);
      $display("PASS CORDIC atan2"); $finish;
    end
endmodule
