`timescale 1ns/1ps
module tb_qcldpc_648_decoder;
  reg clk=0; always #4 clk=~clk;
  reg rst=1,start=0,iv=0,il=0,ordy=1;
  reg signed [6:0] in_llr;
  wire ir,ov,ol,ob,done,ok,synd,busy,err;
  wire [4:0] iters;
  integer k,out_count,cycles;
  cofdm_qcldpc_648_decoder dut(
    .clk,.rst,.start,.in_valid(iv),.in_ready(ir),.in_last(il),.in_llr,
    .out_valid(ov),.out_ready(ordy),.out_last(ol),.out_bit(ob),.done,
    .decode_ok(ok),.syndrome_ok(synd),.iterations_done(iters),.frame_error(err),.busy);
  always @(posedge clk) begin
    if(!rst) begin
      cycles=cycles+1;
      if(err) $fatal(1,"decoder frame error");
      if(ov && ordy) begin
        if(ob!==1'b0) $fatal(1,"decoded information bit %0d is one",out_count);
        if(ol!==(out_count==323)) $fatal(1,"bad output last %0d got=%b",out_count,ol);
        out_count=out_count+1;
      end
      if(done) begin
        if(!ok || !synd || out_count!=324 || iters!=1) $fatal(1,"first-round decode failed ok=%b synd=%b out=%0d iters=%0d",ok,synd,out_count,iters);
        $display("PASS QC-LDPC 648 decoder all-zero with one soft error iters=%0d cycles=%0d",iters,cycles);
        $finish;
      end
    end
  end
  initial begin
    repeat(4) @(negedge clk); rst=0; cycles=0; out_count=0;
    start=1; @(negedge clk); start=0;
    wait(ir);
    for(k=0;k<648;k=k+1) begin
      @(negedge clk); iv=1; il=(k==647); in_llr=7'sd24;
      if(k==3) in_llr=-7'sd24;
      @(posedge clk);
    end
    @(negedge clk); iv=0; il=0;
  end
  initial begin #5000000; $fatal(1,"timeout"); end
endmodule
