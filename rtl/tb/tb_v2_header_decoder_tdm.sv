`timescale 1ns/1ps
module tb_v2_header_decoder_tdm;
  reg clk=0,rst=1,start=0,v=0,last=0; always #5 clk=~clk;
  reg signed [15:0] x; wire ready,hv,hok,crc,err,busy; wire [11:0] len; wire [6:0] seed; wire [1:0] mid;
  reg [15:0] vec[0:191]; integer k,e;
  cofdm_v2_header_decoder_tdm #(.LLR_W(16)) dut(.clk,.rst,.start,.in_valid(v),.in_last(last),.in_ready(ready),.in_llr(x),.header_valid(hv),.header_ok(hok),.payload_bytes(len),.scrambler_seed(seed),.midamble_code(mid),.crc_ok(crc),.header_error(err),.busy);
  task run(input string f,input integer ok,input integer plen,input integer s,input integer m);
    begin $readmemh(f,vec); repeat(2) @(negedge clk); start=1; @(negedge clk); start=0;
      for(k=0;k<192;k=k+1) begin while(!ready) @(negedge clk); v=1;last=k==191;x=vec[k];@(negedge clk);v=0;last=0;end
      wait(hv); #1; if(hok!==ok || (ok&&(len!==plen||seed!==s||mid!==m))) begin $display("FAIL %s",f);e=e+1;end else $display("PASS TDM %s",f); @(negedge clk); end
  endtask
  initial begin e=0;repeat(3)@(negedge clk);rst=0;run("matlab/vectors/v2_header/valid_1.mem",1,1,1,0);run("matlab/vectors/v2_header/valid_2.mem",1,257,93,1);run("matlab/vectors/v2_header/valid_3.mem",1,2048,127,2);run("matlab/vectors/v2_header/invalid_fields.mem",0,0,0,0);if(e)$fatal(1,"TDM errors=%0d",e);$display("PASS low-resource TDM v2 Header");$finish;end
  initial begin #2000000;$fatal(1,"timeout");end
endmodule
