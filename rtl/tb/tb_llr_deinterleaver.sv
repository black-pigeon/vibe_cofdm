`timescale 1ns/1ps
module tb_llr_deinterleaver;
    reg clk=0,rst=1,start=0,iv=0,il=0,ready=0; always #5 clk=~clk;
    reg signed [15:0] x=0; wire ir,ov,ol,busy,error;
    wire signed [15:0] y; integer k,p,count=0,cycle=0;
    reg stalled=0; reg [16:0] held;
    cofdm_llr_deinterleaver dut(.clk,.rst,.start,.in_valid(iv),.in_last(il),.in_ready(ir),.in_llr(x),.out_valid(ov),.out_ready(ready),.out_last(ol),.out_llr(y),.busy,.frame_error(error));
    always @(negedge clk) begin cycle=cycle+1; ready=cycle%9<4; end
    always @(posedge clk) if(!rst) begin
        if(stalled && (!ov || {ol,y}!==held)) $fatal(1,"unstable stalled deinterleaver");
        held={ol,y}; stalled=ov && !ready;
        if(ov && ready) begin
            if(y!==16'((325*count)%384+p*1000) || ol!==(count==383)) $fatal(1,"deinterleave %d",count);
            count=count+1;
        end
    end
    initial begin
        repeat(3) @(negedge clk); rst=0;
        for(p=0;p<3;p=p+1) begin
            count=0; start=1; @(negedge clk); start=0;
            for(k=0;k<384;k=k+1) begin
                if(!ir) $fatal(1,"not ready");
                iv=1; il=k==383; x=16'(k+p*1000); @(negedge clk);
                iv=0; il=0; @(negedge clk);
            end
            wait(!busy); @(negedge clk);
            if(count!=384) $fatal(1,"count %d",count);
        end
        start=1; @(negedge clk); start=0; iv=1; il=1;
        @(negedge clk); iv=0; il=0;
        if(!error || busy || ov) $fatal(1,"early TLAST not rejected");
        $display("PASS deinterleaver: 3 symbols, stalls, bubbles, early TLAST"); $finish;
    end
    initial begin #200000; $fatal(1,"timeout"); end
endmodule
