`timescale 1ns/1ps
module tb_capture_sparse_events;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,s=0,l=0,f=0,h=0,d=0;wire valid,locked;
 cofdm_capture_ctrl dut(.clk,.rst,.sample_valid(1'b0),.stf_hit(s),.stf_index(32'd100),
 .ltf_peak_valid(l),.ltf_peak_score(16'd50000),.ltf_peak_index(32'd292),
 .fine_cfo_valid(f),.header_crc_valid(h),.header_crc_ok(1'b1),.frame_abort(1'b0),
 .frame_done(d),.frame_valid(valid),.capture_locked(locked));
 initial begin
 repeat(4) @(negedge clk);rst=0;s=1;@(negedge clk);s=0;l=1;
 @(negedge clk);l=0;f=1;@(negedge clk);f=0;h=1;
 @(negedge clk);h=0;if(!valid) $fatal(1,"missed header event between samples");
 @(negedge clk);if(!locked) $fatal(1,"not locked");d=1;
 repeat(3) @(negedge clk);if(locked) $fatal(1,"missed done");
 $display("PASS capture events with sample_valid=0");$finish;
 end
endmodule
