`timescale 1ns/1ps
module tb_fine_cfo_phase_to_inc;
    reg clk=0,rst=1,valid=0; reg signed [31:0] phase=0;
    wire out_valid; wire signed [31:0] inc;
    cofdm_fine_cfo_phase_to_inc dut(.clk,.rst,.in_valid(valid),.in_phase(phase),
      .out_valid,.out_phase_inc(inc));
    always #5 clk=~clk;
    initial begin
      #12 rst=0;
      // 12.5 kHz at 15.36 MHz: phase = 2*pi*288*fc/Fs in Q3.29.
      @(negedge clk); phase=32'sd790607678; valid=1;
      @(posedge clk); #1 valid=0;
      wait(out_valid);
      // NCO increment = -fc/Fs*2^32, matching the receiver correction sign.
      if (inc > -32'sd3400000 || inc < -32'sd3500000)
        $fatal(1,"phase increment=%0d",inc);
      $display("PASS phase-to-NCO increment=%0d",inc); $finish;
    end
endmodule
