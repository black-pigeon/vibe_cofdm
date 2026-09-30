`timescale 1ns/1ps
module tb_ltf_fft_stream_adapter;
    reg clk=0,rst=1,valid=0,last=0; reg signed [15:0] re=0,im=0;
    wire ready,mvalid,start,sym,mlast,active,error; wire [7:0] bin;
    cofdm_ltf_fft_stream_adapter dut(.clk,.rst,.s_valid(valid),.s_ready(ready),
      .s_last(last),.s_re(re),.s_im(im),.m_valid(mvalid),.m_symbol_start(start),
      .m_symbol_id(sym),.m_last(mlast),.m_bin_index(bin),.m_bin_active(active),
      .m_re(),.m_im(),.frame_error(error));
    always #5 clk=~clk;
    integer k; reg saw1=0,saw2=0;
    task send(input l);
      begin @(negedge clk); valid=1; last=l; @(posedge clk); #1 valid=0; last=0; end
    endtask
    always @(posedge clk) if(mvalid) begin
      if (start && bin!=0) $fatal(1,"bad start bin");
      if (sym) saw2=1; else saw1=1;
    end
    initial begin
      #12 rst=0;
      for(k=0;k<256;k=k+1) send(k==255);
      for(k=0;k<256;k=k+1) send(k==255);
      repeat(2) @(posedge clk);
      if(!saw1 || !saw2 || error) $fatal(1,"adapter failure saw1=%0d saw2=%0d err=%0d",saw1,saw2,error);
      $display("PASS LTF FFT stream adapter"); $finish;
    end
endmodule
