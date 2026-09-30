`timescale 1ns/1ps
module tb_ltf_fine_cfo_chain_zc;
  localparam [255:0] ACTIVE = {256{1'b1}};
  reg clk=0,rst=1,v=0,last=0; reg signed [15:0] re=0,im=0;
  wire ready,stored,sv,iv,err; wire signed [63:0] sr,si; wire [31:0] cnt;
  wire signed [31:0] phase,inc; wire signed [15:0] t1r,t1i,t2r,t2i;
  reg [7:0] bin;
  cofdm_ltf_freq_rom rom(.addr(bin),.t1_re(t1r),.t1_im(t1i),.t2_re(t2r),.t2_im(t2i));
  cofdm_ltf_fine_cfo_chain #(.ACTIVE_MASK(ACTIVE),.USE_ROT_ROM(1)) dut(
    .clk,.rst,.fft_out_valid(v),.fft_out_ready(ready),.fft_out_last(last),.fft_out_re(re),.fft_out_im(im),
    .rot_re(16'sd0),.rot_im(16'sd0),.ltf1_stored(stored),.fine_sum_valid(sv),.fine_sum_re(sr),.fine_sum_im(si),
    .active_count(cnt),.phase_valid(iv),.phase,.phase_inc_valid(),.phase_inc(inc),.frame_error(err));
  always #5 clk=~clk;
  integer k;
  reg saw_phase=0;
  always @(posedge clk) if (iv) saw_phase=1;
  task send(input [7:0] b,input sid,input la);
    begin
      @(negedge clk); bin=b; v=1; last=la;
      #1; if (!sid) begin re=t1r; im=t1i; end
           else begin re=-t2i; im=t2r; end // Y2 = j*T2, residual phase +pi/2
      @(posedge clk); #1 v=0; last=0;
    end
  endtask
  initial begin
    #12 rst=0;
    for(k=0;k<256;k=k+1) send(k,0,k==255);
    for(k=0;k<256;k=k+1) send(k,1,k==255);
    repeat(50) @(posedge clk);
    if(!saw_phase || err || cnt!=256) $fatal(1,"ZC fine CFO failed valid=%0d err=%0d count=%0d",saw_phase,err,cnt);
    if (phase < 32'sh32000000 || phase > 32'sh33000000)
      $fatal(1,"ZC phase=%0d",phase);
    $display("PASS per-bin ZC dual-LTF phase=%0d",phase); $finish;
  end
endmodule
