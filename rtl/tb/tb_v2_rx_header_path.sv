`timescale 1ns/1ps
module tb_v2_rx_header_path;
  reg clk=0,rst=1,fs=0,v=0,h=0,last=0,pr=1; always #5 clk=~clk;
  reg signed [15:0] x; wire sr,pv,pl,hv,ok,crc,err,busy; wire signed [15:0] py; wire [11:0] len; wire [6:0] seed; wire [1:0] mid;
  reg [15:0] hdr[0:191]; integer k;
  cofdm_v2_rx_header_path dut(.clk,.rst,.frame_start(fs),.stream_valid(v),.stream_header(h),.stream_last(last),.stream_llr(x),.stream_ready(sr),.payload_valid(pv),.payload_last(pl),.payload_llr(py),.payload_ready(pr),.header_valid(hv),.header_ok(ok),.crc_ok(crc),.payload_bytes(len),.scrambler_seed(seed),.midamble_code(mid),.header_error(err),.busy);
  initial begin
    $readmemh("matlab/vectors/v2_header/valid_2.mem",hdr); repeat(3) @(negedge clk); rst=0; fs=1; @(negedge clk); fs=0;
    for(k=0;k<192;k=k+1) begin h=1;while(!sr) @(negedge clk);v=1;last=k==191;x=hdr[k];@(negedge clk);v=0;h=0;last=0;end
    wait(hv); if(!ok || len!=257) $fatal(1,"header path fail");
    repeat(3) begin while(!sr) @(negedge clk);v=1;h=0;last=0;x=16'sd100;#1;if(!pv) $fatal(1,"payload was not released");@(negedge clk);v=0;end
    $display("PASS v2 RX Header path releases payload after CRC/fields");$finish;
  end
  initial begin #1000000;$fatal(1,"timeout");end
endmodule
