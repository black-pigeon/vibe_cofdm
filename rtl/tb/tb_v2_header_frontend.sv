`timescale 1ns/1ps
module tb_v2_header_frontend;
  reg clk=0,rst=1,fs=0,v=0,last=0; always #5 clk=~clk;
  reg signed [15:0] x; wire ready,hv,ok,crc,err,busy; wire [11:0] len; wire [6:0] seed; wire [1:0] mid;
  reg [15:0] mem[0:191]; integer k;
  cofdm_v2_header_frontend dut(.clk,.rst,.frame_start(fs),.in_valid(v),.in_last(last),.in_llr(x),.in_ready(ready),
    .header_valid(hv),.header_ok(ok),.crc_ok(crc),.payload_bytes(len),.scrambler_seed(seed),.midamble_code(mid),.header_error(err),.busy);
  initial begin
    $readmemh("matlab/vectors/v2_header/valid_2.mem",mem); repeat(3) @(negedge clk); rst=0; fs=1; @(negedge clk); fs=0;
    for(k=0;k<192;k=k+1) begin while(!ready) @(negedge clk); v=1;last=k==191;x=mem[k];@(negedge clk);v=0;last=0;end
    wait(hv); if(!ok || len!=257 || seed!=93 || mid!=1) $fatal(1,"frontend decode failed");
    $display("PASS v2 Header frontend integration len=%d seed=%d mid=%d",len,seed,mid);$finish;
  end
  initial begin #1000000;$fatal(1,"timeout");end
endmodule
