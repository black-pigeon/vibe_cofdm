`timescale 1ns/1ps
module tb_qcldpc_codeword_scheduler;
  reg clk=0; always #4 clk=~clk;
  reg rst=1,iv=0,il=0,ordy=1; reg signed [6:0] x=24;
  wire ir,ov,ol,ob,ok,busy; wire [4:0] it; wire [15:0] oi,q;
  wire done,err;
  integer i,words=0,bits=0,cycles=0;
  localparam integer WORDS_TARGET=8;
  cofdm_qcldpc_codeword_scheduler #(.LANES(2),.FIFO_DEPTH(3)) dut(
    .clk,.rst,.in_valid(iv),.in_ready(ir),.in_last(il),.in_llr(x),
    .out_valid(ov),.out_ready(ordy),.out_last(ol),.out_bit(ob),
    .out_decode_ok(ok),.out_iterations(it),.out_codeword_index(oi),
    .codeword_done(done),.frame_error(err),.busy,.queued_codewords(q));
  always @(posedge clk) begin
    if(!rst) begin
      cycles=cycles+1;
      if(err) $fatal(1,"scheduler frame error");
      if(ov && ordy) begin
        if(ob!==0 || oi!==words || ol!==(bits%324==323))
          $fatal(1,"output mismatch word=%0d bit=%0d seq=%0d bit=%b last=%b",words,bits,oi,ob,ol);
        bits=bits+1;
        if(ol) begin
          if(!ok || it!=1) $fatal(1,"word %0d status ok=%b it=%0d",words,ok,it);
          words=words+1;bits=0;
        end
      end
      if(words==WORDS_TARGET) begin
        $display("PASS scheduler %0d codewords ordered across 2 lanes with FIFO wrap cycles=%0d",WORDS_TARGET,cycles);
        $finish;
      end
    end
  end
  initial begin
    repeat(4) @(negedge clk);rst=0;
    for(i=0;i<WORDS_TARGET*648;i=i+1) begin
      while(!ir) @(negedge clk);
      iv=1;il=(i%648==647);@(negedge clk);iv=0;il=0;
    end
  end
  initial begin #3000000;$fatal(1,"timeout words=%0d bits=%0d queued=%0d",words,bits,q);end
endmodule
