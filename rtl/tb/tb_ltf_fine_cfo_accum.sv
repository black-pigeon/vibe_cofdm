`timescale 1ns/1ps
module tb_ltf_fine_cfo_accum;
    reg clk=0,rst=1,valid=0,start=0,last=0,sym=0,active=0;
    reg [7:0] bin=0; reg signed [15:0] re=0,im=0;
    reg signed [15:0] rot_re=16'sd32767,rot_im=0;
    wire stored,out_valid; wire signed [63:0] sum_re,sum_im; wire [31:0] count;
    cofdm_ltf_fine_cfo_accum dut(.clk,.rst,.fft_valid(valid),.fft_symbol_start(start),
      .fft_last(last),.fft_symbol_id(sym),.fft_bin_index(bin),.fft_bin_active(active),
      .fft_re(re),.fft_im(im),.rot_re,.rot_im,.ltf1_stored(stored),
      .fine_sum_valid(out_valid),.fine_sum_re(sum_re),.fine_sum_im(sum_im),.active_count(count));
    always #5 clk=~clk;
    integer k; reg seen_valid=0; reg signed [63:0] seen_re=0,seen_im=0; reg [31:0] seen_count=0;
    task send;
      input [7:0] b; input s,l,a; input si;
      begin
        @(negedge clk); valid=1; bin=b; start=s; last=l; active=a; sym=si;
        re=si ? 16'sd0 : 16'sd1000; im=si ? 16'sd1000 : 16'sd0;
        @(posedge clk); #1; valid=0; start=0; last=0; active=0;
      end
    endtask
    initial begin
      #12 rst=0;
      // LTF1 is real 1000; LTF2 is +j1000. Cross term is +j*1e6.
      for(k=0;k<256;k=k+1) send(k,k==0,k==255,1,0);
      if(!stored) $fatal(1,"LTF1 was not stored");
      for(k=0;k<256;k=k+1) send(k,k==0,k==255,1,1);
      repeat(8) @(posedge clk);
      if(!seen_valid) $fatal(1,"fine sum valid missing");
      if(seen_count!=256) $fatal(1,"active count=%0d",seen_count);
      if(seen_re < -1000 || seen_re > 1000) $fatal(1,"sum re=%0d",seen_re);
      if(seen_im < 64'sd250000000 || seen_im > 64'sd270000000)
        $fatal(1,"sum im=%0d",seen_im);
      $display("PASS dual LTF fine CFO accumulator re=%0d im=%0d count=%0d",seen_re,seen_im,seen_count);
      $finish;
    end
    always @(posedge clk) if(out_valid) begin seen_valid=1; seen_re=sum_re; seen_im=sum_im; seen_count=count; end
endmodule
