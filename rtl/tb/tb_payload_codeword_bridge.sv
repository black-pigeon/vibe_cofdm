`timescale 1ns/1ps
module tb_payload_codeword_bridge;
  reg clk=0; always #4 clk=~clk;
  reg rst=1,fs=0,iv=0,il=0,cf=0,cl=0,ordy=1;
  reg signed [6:0] x;
  reg [15:0] n_cw=1;
  wire ir,ov,ol,ob,cwd,fd,fe,busy,ok;
  wire [15:0] ci; wire [4:0] it;
  integer k,count=0,cycles=0;
  cofdm_payload_codeword_bridge #(.INPUT_LLR_W(7),.INPUT_SHIFT(0)) dut(
    .clk,.rst,.frame_start(fs),.n_codewords(n_cw),.in_valid(iv),.in_ready(ir),
    .in_last(il),.in_cw_first(cf),.in_cw_last(cl),.in_llr(x),.out_valid(ov),
    .out_ready(ordy),.out_last(ol),.out_bit(ob),.codeword_done(cwd),.frame_done(fd),
    .frame_error(fe),.busy,.codeword_index(ci),.decoder_ok(ok),.decoder_iterations(it));
  always @(posedge clk) if(!rst) begin
    cycles=cycles+1;
    if(fe) $fatal(1,"payload bridge error");
    if(ov && ordy) begin
      if(ob!==1'b0) $display("decoded bit %0d is one",count);
      if(ol!==(count==323)) $fatal(1,"bad output last %0d",count);
      count=count+1;
    end
    if(fd) begin
      if(count!=324 || !ok || ci!=0) $fatal(1,"bad frame result count=%0d ok=%b ci=%0d",count,ok,ci);
      $display("PASS payload codeword bridge, decoded=%0d cycles=%0d",count,cycles);
      $finish;
    end
  end
  initial begin
    repeat(4) @(negedge clk); rst=0;
    wait(ir);
    for(k=0;k<648;k=k+1) begin
      @(negedge clk); iv=1; il=(k==647); cf=(k==0); cl=(k==647); x=7'sd24;
      if(k==3) x=-7'sd24;
      @(posedge clk);
    end
    @(negedge clk); iv=0;il=0;cf=0;cl=0;
  end
  initial begin #5000000; $fatal(1,"timeout"); end
endmodule
