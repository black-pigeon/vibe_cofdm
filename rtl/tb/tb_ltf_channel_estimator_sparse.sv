`timescale 1ns/1ps
// Guard/DC bins are deliberately excluded and the final natural FFT bin is
// inactive.  The estimator must still finish on fft_last and report the
// number of measured carriers rather than treating the guard as an error.
module tb_ltf_channel_estimator_sparse;
  localparam [255:0] MASK = {1'b0,{255{1'b1}}};
  reg clk=0,rst=1,v=0,id=0,last=0; reg [7:0] bin=0;
  reg signed [15:0] re=0,im=0;
  wire ready,cv,cl,done,err,cr,nv; wire signed [17:0] hr,hi;
  wire [47:0] noise_var; wire [31:0] noise_count;
  wire signed [15:0] t1r,t1i,t2r,t2i;
  cofdm_ltf_freq_rom rom(.addr(bin),.t1_re(t1r),.t1_im(t1i),.t2_re(t2r),.t2_im(t2i));
  cofdm_ltf_channel_estimator #(.ACTIVE_MASK(MASK)) dut(
    .clk,.rst,.fft_valid(v),.fft_symbol_id(id),.fft_last(last),.fft_bin_index(bin),
    .fft_bin_active((t1r!=0)||(t1i!=0)),.fft_re(re),.fft_im(im),.fft_ready(ready),
    .channel_valid(cv),.channel_last(cl),.channel_bin(),.channel_re(hr),.channel_im(hi),
    .channel_done(done),.channel_error(err),.noise_variance(noise_var),
    .noise_valid(nv),.noise_sample_count(noise_count),.h_rd_en(1'b0),.h_rd_bin(8'd0),
    .h_rd_re(),.h_rd_im(),.h_valid(),.channel_ready(cr));
  always #5 clk=~clk;
  integer k; reg saw_done=0,saw_noise=0,saw_last=0; reg [31:0] seen_count=0;
  task send(input [7:0] b,input si,input la);
    begin @(negedge clk); v=1; id=si; last=la; bin=b;
      #1; if (si) begin re=t2r; im=t2i; end else begin re=t1r; im=t1i; end
      @(posedge clk); #1; v=0; last=0;
    end
  endtask
  always @(posedge clk) begin
    if (cl) saw_last=1;
    if (done) saw_done=1;
    if (nv) begin saw_noise=1; seen_count=noise_count; end
  end
  initial begin
    #12 rst=0;
    for(k=0;k<256;k=k+1) send(k,0,k==255);
    for(k=0;k<256;k=k+1) send(k,1,k==255);
    repeat(8) @(posedge clk);
    if (!saw_done || !saw_noise || !saw_last || !cr || err || seen_count != 199)
      $fatal(1,"sparse estimator failed done=%0d nv=%0d last=%0d ready=%0d err=%0d count=%0d",
             saw_done,saw_noise,saw_last,cr,err,seen_count);
    $display("PASS sparse-mask LTF channel completion"); $finish;
  end
endmodule
