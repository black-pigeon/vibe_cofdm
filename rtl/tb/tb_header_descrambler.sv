`timescale 1ns/1ps
module tb_header_descrambler;
    reg clk=0,rst=1,start=0,v=0; always #5 clk=~clk;
    reg signed [15:0] x=0; wire ready,ov; wire signed [15:0] y;
    reg bits[0:767]; integer k,p,expected;
    cofdm_header_descrambler dut(.clk,.rst,.frame_start(start),.in_valid(v),.in_llr(x),.in_ready(ready),.out_valid(ov),.out_llr(y));
    initial begin
        $readmemh("matlab/vectors/pre_ldpc_stream/header_bits.mem",bits);
        repeat(3) @(negedge clk); rst=0;
        for(p=0;p<2;p=p+1) begin
            start=1; @(negedge clk); start=0;
            for(k=0;k<768;k=k+1) begin
                x=(k%9==0)?-16'sd32768:16'(k-400);
                expected=bits[k]?-$signed(x):$signed(x);
                if(expected==32768) expected=32767;
                v=1; @(posedge clk); #1;
                if(!ready || !ov || y!==16'(expected)) $fatal(1,"descrambler %d",k);
                @(negedge clk); v=0; @(negedge clk);
            end
        end
        $display("PASS MATLAB header descrambler 2 x 768 bits, saturation, bubbles"); $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
