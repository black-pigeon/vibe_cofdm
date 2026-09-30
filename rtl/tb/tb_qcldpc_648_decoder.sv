`timescale 1ns/1ps
module tb_qcldpc_648_decoder;
  reg clk=0; always #4 clk=~clk;
  reg rst=1,start=0,iv=0,il=0,ordy=1;
  reg signed [6:0] in_llr;
  wire ir,ov,ol,ob,done,ok,synd,busy,err;
  wire [4:0] iters;
  integer k,out_count,cycles;
  reg [7:0] flip [0:19];
  cofdm_qcldpc_648_decoder dut(
    .clk,.rst,.start,.in_valid(iv),.in_ready(ir),.in_last(il),.in_llr,
    .out_valid(ov),.out_ready(ordy),.out_last(ol),.out_bit(ob),.done,
    .decode_ok(ok),.syndrome_ok(synd),.iterations_done(iters),.frame_error(err),.busy);
  always @(posedge clk) begin
    if(!rst) begin
      cycles=cycles+1;
      if(err) $fatal(1,"decoder frame error");
      if(ov && ordy) begin
        if(ob!==1'b0) begin $display("decoded information bit %0d is one",out_count); end
        if(ol!==(out_count==323)) $display("bad output last %0d got=%b",out_count,ol);
        out_count=out_count+1;
      end
      if(done) begin
        if(!ok || !synd || out_count!=324) $fatal(1,"decode failed ok=%b synd=%b out=%0d iters=%0d",ok,synd,out_count,iters);
        $display("PASS QC-LDPC 648 decoder all-zero with one soft error iters=%0d cycles=%0d",iters,cycles);
        $finish;
      end
    end
  end
  initial begin
    flip[0]=3; flip[1]=17; flip[2]=31; flip[3]=52; flip[4]=77;
    flip[5]=101; flip[6]=129; flip[7]=155; flip[8]=179; flip[9]=203;
    flip[10]=227; flip[11]=251; flip[12]=277; flip[13]=301; flip[14]=329;
    flip[15]=353; flip[16]=401; flip[17]=477; flip[18]=571; flip[19]=643;
    repeat(4) @(negedge clk); rst=0; cycles=0; out_count=0;
    start=1; @(negedge clk); start=0;
    wait(ir);
    for(k=0;k<648;k=k+1) begin
      @(negedge clk); iv=1; il=(k==647); in_llr=7'sd24;
        if(k==flip[0]) begin
        if(k==flip[0]||k==flip[1]||k==flip[2]||k==flip[3]||k==flip[4]||
           k==flip[5]||k==flip[6]||k==flip[7]||k==flip[8]||k==flip[9]||
           k==flip[10]||k==flip[11]||k==flip[12]||k==flip[13]||k==flip[14]||
           k==flip[15]||k==flip[16]||k==flip[17]||k==flip[18]||k==flip[19]) in_llr=-7'sd24;
      end
      @(posedge clk);
    end
    @(negedge clk); iv=0; il=0;
  end
  initial begin #5000000; $fatal(1,"timeout"); end
endmodule
