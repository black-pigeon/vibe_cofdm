`timescale 1ns/1ps
module tb_fusion_kernel;
    localparam W=8;
    reg clk=0, rst=1, in_valid=0, in_last=0, fast=0;
    reg [1:0] rot=0;
    reg signed [W-1:0] old_re,old_im,fresh_re,fresh_im;
    wire out_valid,out_last; wire signed [W-1:0] next_re,next_im;
    cofdm_fusion_lane #(.W(W),.FUSE_SHIFT(2)) dut(
      .clk,.rst,.in_valid,.in_last,.rot_code(rot),.fast_update(fast),
      .old_re,.old_im,.fresh_re,.fresh_im,.out_valid,.out_last,.next_re,.next_im);
    always #5 clk=~clk;
    task apply;
      input integer o_r,o_i,f_r,f_i; input [1:0] q; input integer quick; input integer last;
      begin
        @(negedge clk); old_re=o_r;old_im=o_i;fresh_re=f_r;fresh_im=f_i;rot=q;fast=quick;in_last=last;in_valid=1;
        @(posedge clk); #1;
        @(negedge clk); in_valid=0;in_last=0;
      end
    endtask
    initial begin
      old_re=0;old_im=0;fresh_re=0;fresh_im=0; rot=0; fast=0;
      #12 rst=0;
      // q=0, alpha=1/4: (10,20) -> (12,15) with truncation toward -inf.
      apply(10,20,18,0,0,0,0);
      if (!out_valid || next_re!==8'sd12 || next_im!==8'sd15) $fatal(1,"q0");
      // q=1 (-j): fresh (0,16) -> (16,0), alpha=1 -> (16,0).
      apply(0,0,0,16,1,1,1);
      if (!out_valid || !out_last || next_re!==8'sd16 || next_im!==8'sd0) $fatal(1,"q1");
      $display("PASS fusion lane"); $finish;
    end
endmodule
