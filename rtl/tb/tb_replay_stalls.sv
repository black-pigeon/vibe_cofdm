`timescale 1ns/1ps
module tb_replay_stalls;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,sv=0,go=0,ext=0,ready=0;
 reg [15:0] ns=3;reg [31:0] idx=100;
 reg signed [15:0] x=0;
 wire v,ss,busy,done,err;wire signed [15:0] y,im;wire [15:0] sym;
 integer cycle=0,w=0,count=0,phase=0,prefix_end=-1;reg held_v=0;reg [48:0] held;
 cofdm_pre_fft_stream_replay #(.NFFT(8),.CP_LEN(2),.BUFFER_DEPTH(1024),.SYMBOL_INDEX_W(16)) dut(
 .clk,.rst,.sample_valid(sv),.sample_re(x),.sample_im(-x),.replay_start(go),
 .replay_start_index(idx),.replay_symbol_count(ns),.replay_extend_valid(ext),
 .out_valid(v),.out_ready(ready),.out_re(y),.out_im(im),.out_symbol_start(ss),
 .out_symbol_index(sym),.replay_busy(busy),.replay_done(done),.replay_error(err));
 always @(negedge clk) if(!rst) begin
   cycle=cycle+1;sv=(cycle%8==0);if(sv) begin x=16'(w);w=w+1;end
   ready=phase==0 && (cycle%117<70);
 end
 always @(posedge clk) if(!rst && phase==0) begin
   if(err) $fatal(1,"unexpected overwrite");
   if(held_v && (!v || {sym,ss,im,y}!==held)) $fatal(1,"hold changed");
   held_v=v && !ready;held={sym,ss,im,y};
   if(v && ready) begin
     if(y!==16'(100+count) || im!==-16'(100+count) || ss!==(count%10==0) || sym!==16'(count/10)) $fatal(1,"sample %d got %d",count,y);
     count=count+1;
   end
 end
 initial begin
   repeat(5) @(negedge clk);rst=0;
   wait(w==200);@(negedge clk);go=1;@(negedge clk);go=0;
   wait(done);@(negedge clk);if(count!=30) $fatal(1,"prefix");
   repeat(1600) @(negedge clk);ns=1000;ext=1;@(negedge clk);ext=0;
   wait(done);@(negedge clk);if(count!=10000) $fatal(1,"extension");
   phase=1;idx=32'(w-100);ns=1000;go=1;@(negedge clk);go=0;
   wait(err);repeat(5) @(negedge clk);if(busy || v) $fatal(1,"overrun not stopped");
   $display("PASS ring: prefix/late extension, sparse writer, stalls, >RAM frame, overwrite abort");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
