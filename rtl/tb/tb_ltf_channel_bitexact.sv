`timescale 1ns/1ps
module tb_ltf_channel_bitexact;
  parameter VEC_DIR = "matlab/vectors/ltf_channel";
  reg clk=0, rst=1, v=0, id=0, last=0;
  reg [7:0] bin=0;
  reg signed [15:0] re=0, im=0;
  reg signed [15:0] y1r[0:255], y1i[0:255], y2r[0:255], y2i[0:255];
  reg signed [17:0] eh_r[0:255], eh_i[0:255];
  reg [47:0] env[0:0];
  wire signed [15:0] t1r,t1i,t2r,t2i;
  wire cv,cl,done,err,ready,cr,nv; wire [7:0] cb;
  wire signed [17:0] hr,hi; wire [47:0] noise_var; wire [31:0] noise_count;
  cofdm_ltf_freq_rom rom(.addr(bin),.t1_re(t1r),.t1_im(t1i),.t2_re(t2r),.t2_im(t2i));
  cofdm_ltf_channel_estimator #(.H_FRAC_BITS(14)) dut(
    .clk,.rst,.fft_valid(v),.fft_symbol_id(id),.fft_last(last),.fft_bin_index(bin),
    .fft_bin_active((t1r!=0)||(t1i!=0)),.fft_re(re),.fft_im(im),.fft_ready(ready),
    .channel_valid(cv),.channel_last(cl),.channel_bin(cb),.channel_re(hr),.channel_im(hi),
    .channel_done(done),.channel_error(err),.noise_variance(noise_var),
    .noise_valid(nv),.noise_sample_count(noise_count),.h_rd_en(1'b0),.h_rd_bin(8'd0),
    .h_rd_re(),.h_rd_im(),.h_valid(),.channel_ready(cr));
  always #5 clk=~clk;
  integer k, errors, count; reg done_seen, noise_seen;
  task send(input integer b,input integer sid);
    begin @(negedge clk); bin=b[7:0]; id=sid; last=(b==255); v=1;
      if (sid==0) begin re=y1r[b]; im=y1i[b]; end
      else begin re=y2r[b]; im=y2i[b]; end
      @(posedge clk); #1; v=0; last=0;
    end
  endtask
  always @(posedge clk) begin
    #1;
    if (cv) begin
      count=count+1;
      if (hr !== eh_r[cb] || hi !== eh_i[cb]) begin
        $display("FAIL H bin=%0d got=%0d+j%0d exp=%0d+j%0d",cb,hr,hi,eh_r[cb],eh_i[cb]);
        errors=errors+1;
      end
      if (cl) begin
        if (!done) $display("WARN channel_last did not coincide with done");
        done_seen=1;
      end
    end
    if (nv) begin
      noise_seen=1;
      if (noise_var !== env[0]) begin
        $display("FAIL noise variance got=%h exp=%h",noise_var,env[0]); errors=errors+1;
      end
      if (noise_count !== 200) begin
        $display("FAIL noise count got=%0d exp=200",noise_count); errors=errors+1;
      end
    end
  end
  initial begin
    $readmemh({VEC_DIR,"/ltf1_re.hex"},y1r);
    $readmemh({VEC_DIR,"/ltf1_im.hex"},y1i);
    $readmemh({VEC_DIR,"/ltf2_re.hex"},y2r);
    $readmemh({VEC_DIR,"/ltf2_im.hex"},y2i);
    $readmemh({VEC_DIR,"/expected_h_re.hex"},eh_r);
    $readmemh({VEC_DIR,"/expected_h_im.hex"},eh_i);
    $readmemh({VEC_DIR,"/expected_noise.hex"},env);
    errors=0; count=0; done_seen=0; noise_seen=0;
    #12 rst=0;
    for(k=0;k<256;k=k+1) send(k,0);
    for(k=0;k<256;k=k+1) send(k,1);
    repeat(20) @(posedge clk);
    if (count != 200 || !done_seen || !noise_seen || !cr || err) begin
      $display("FAIL status count=%0d done=%0d noise=%0d ready=%0d err=%0d",count,done_seen,noise_seen,cr,err);
      errors=errors+1;
    end
    if (errors != 0) $fatal(1,"LTF channel bit-exact errors=%0d",errors);
    $display("PASS LTF channel bit-exact vector check bins=%0d",count); $finish;
  end
endmodule
