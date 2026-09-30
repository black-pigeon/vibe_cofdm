`timescale 1ns/1ps
module tb_ltf_channel_estimator;
  reg clk=0,rst=1,v=0,id=0,last=0; reg [7:0] bin=0; reg signed [15:0] re=0,im=0;
  wire ready,cv,cl,done,err,cr; wire signed [17:0] hr,hi; wire [7:0] cb;
  wire signed [17:0] rdhr,rdhi; wire rdv;
  wire [47:0] noise_var; wire noise_v; wire [31:0] noise_count;
  wire signed [15:0] t1r,t1i,t2r,t2i;
  cofdm_ltf_freq_rom rom(.addr(bin),.t1_re(t1r),.t1_im(t1i),.t2_re(t2r),.t2_im(t2i));
  cofdm_ltf_channel_estimator #(.ACTIVE_MASK({256{1'b1}})) dut(
    .clk,.rst,.fft_valid(v),.fft_symbol_id(id),.fft_last(last),.fft_bin_index(bin),
    .fft_bin_active((t1r!=0)||(t1i!=0)),.fft_re(re),.fft_im(im),.fft_ready(ready),
    .channel_valid(cv),.channel_last(cl),.channel_bin(cb),.channel_re(hr),.channel_im(hi),
    .channel_done(done),.channel_error(err),.h_rd_en(1'b0),.h_rd_bin(8'd0),
    .h_rd_re(rdhr),.h_rd_im(rdhi),.h_valid(rdv),.channel_ready(cr),
    .noise_variance(noise_var),.noise_valid(noise_v),.noise_sample_count(noise_count));
  always #5 clk=~clk;
  integer k; reg saw=0; reg saw_noise=0; reg [31:0] noise_count_seen=0; reg [47:0] noise_seen=0;
  task send(input [7:0] b,input si,input la);
    begin
      @(negedge clk); v=1; id=si; last=la; bin=b;
      #1; if (si) begin re=t2r; im=t2i; end else begin re=t1r; im=t1i; end
      @(posedge clk); #1; v=0; last=0;
    end
  endtask
  always @(posedge clk) if (cv) begin
    if (hr < 18'sd30000 || hr > 18'sd33000 || hi < -18'sd200 || hi > 18'sd200)
      $fatal(1,"bad H bin=%0d H=%0d+j%0d",cb,hr,hi);
    if (cl) saw=1;
  end
  always @(posedge clk) if (noise_v) begin
    saw_noise=1; noise_count_seen=noise_count; noise_seen=noise_var;
  end
  initial begin
    #12 rst=0;
    for(k=0;k<256;k=k+1) send(k,0,k==255);
    for(k=0;k<256;k=k+1) send(k,1,k==255);
    repeat(8) @(posedge clk);
    if(!saw || err || !cr || !saw_noise || noise_count_seen != 200 || noise_seen != 0)
      $fatal(1,"channel estimator failed done=%0d saw=%0d err=%0d ready=%0d nv=%0d count=%0d var=%0d",
             done,saw,err,cr,saw_noise,noise_count_seen,noise_seen);
    $display("PASS dual-LTF channel estimate"); $finish;
  end
endmodule
