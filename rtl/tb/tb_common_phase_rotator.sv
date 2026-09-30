`timescale 1ns/1ps
module tb_common_phase_rotator;
  reg clk=0,rst=1,v=0; reg signed [31:0] phase; reg signed [15:0] ir,ii;
  wire ov; wire signed [15:0] orr,oii; integer errors=0;
  cofdm_common_phase_rotator dut(.clk,.rst,.in_valid(v),.phase,.in_re(ir),.in_im(ii),.out_valid(ov),.out_re(orr),.out_im(oii));
  always #5 clk=~clk;
  task send(input integer ph,input integer xr,input integer xi); begin
    @(negedge clk); phase=ph; ir=xr; ii=xi; v=1; @(posedge clk); #1; v=0; end endtask
  task check_vec(input integer ph,input integer xr,input integer xi,input integer er,input integer ei); begin
    send(ph,xr,xi); wait(ov===1'b1); #1;
    if(orr<er-25 || orr>er+25 || oii<ei-25 || oii>ei+25) begin
      $display("FAIL phase=%h got=%0d,%0d exp=%0d,%0d",ph,orr,oii,er,ei); errors=errors+1;
    end
  end endtask
  initial begin
    #12 rst=0;
    // zero phase preserves the sample; +pi/2 applies exp(-j*pi/2): 1+j -> 1-j.
    check_vec(32'sh00000000,12000,7000,12000,7000);
    check_vec(32'sh40000000,12000,7000,7000,-12000);
    check_vec(32'sh80000000,12000,7000,-12000,-7000);
    if(errors) $fatal(1,"phase rotator errors=%0d",errors); $display("PASS common phase rotator"); $finish;
  end
endmodule
