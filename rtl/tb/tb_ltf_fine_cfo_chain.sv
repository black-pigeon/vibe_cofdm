`timescale 1ns/1ps
module tb_ltf_fine_cfo_chain;
    reg clk=0,rst=1,valid=0,last=0; reg signed [15:0] re=0,im=0;
    wire ready,stored,sum_valid,phase_valid,inc_valid,error;
    wire signed [63:0] sum_re,sum_im; wire [31:0] count;
    wire signed [31:0] phase,inc;
    cofdm_ltf_fine_cfo_chain #(.USE_ROT_ROM(0)) dut(.clk,.rst,.fft_out_valid(valid),.fft_out_ready(ready),
      .fft_out_last(last),.fft_out_re(re),.fft_out_im(im),.rot_re(16'sd32767),
      .rot_im(16'sd0),.ltf1_stored(stored),.fine_sum_valid(sum_valid),
      .fine_sum_re(sum_re),.fine_sum_im(sum_im),.active_count(count),
      .phase_valid,.phase,.phase_inc_valid(inc_valid),.phase_inc(inc),.frame_error(error));
    always #5 clk=~clk;
    integer k; reg saw_phase=0,saw_inc=0;
    task send(input [7:0] b, input l, input si);
      begin @(negedge clk); valid=1; last=l;
        if(si) begin re=0; im=1000; end else begin re=1000; im=0; end
        @(posedge clk); #1 valid=0; last=0; end
    endtask
    always @(posedge clk) begin
      if (phase_valid) begin
        saw_phase=1;
        if (phase < 32'sh32300000 || phase > 32'sh32500000)
          $fatal(1,"phase=%0d",phase);
      end
      if (inc_valid) begin saw_inc=1;
        if (inc > -32'sd3600000 || inc < -32'sd3800000)
          $fatal(1,"inc=%0d",inc);
      end
    end
    initial begin
      #12 rst=0;
      for(k=0;k<256;k=k+1) send(k,k==255,0);
      for(k=0;k<256;k=k+1) send(k,k==255,1);
      repeat(40) @(posedge clk);
      if(!stored || !saw_phase || !saw_inc || error || count!=256)
        $fatal(1,"chain failure stored=%0d phase=%0d inc=%0d err=%0d count=%0d",stored,saw_phase,saw_inc,error,count);
      $display("PASS integrated LTF fine CFO chain phase=%0d inc=%0d",phase,inc); $finish;
    end
endmodule
