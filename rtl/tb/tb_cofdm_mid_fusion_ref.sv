`timescale 1ns/1ps
module tb_cofdm_mid_fusion_ref;
    localparam integer W=18, N=200;
    reg clk=0, rst=1, start=0, sv=0, sl=0, sp=0, ready=0;
    reg signed [W-1:0] old_re=0, old_im=0, fresh_re=0, fresh_im=0;
    reg [W-1:0] old_var=1, fresh_var=1;
    wire busy, done, valid, last, full, empty;
    wire signed [W-1:0] out_re, out_im;
    integer i, count;
    cofdm_mid_fusion_ref_top #(.W(W),.N_ACTIVE(N)) dut (
      .clk,.rst,.start,.sample_valid(sv),.sample_last(sl),.sample_pilot(sp),
      .old_re,.old_im,.fresh_re,.fresh_im,.old_var,.fresh_var,
      .busy,.done,.result_ready(ready),.result_valid(valid),.result_last(last),
      .result_re(out_re),.result_im(out_im),.fifo_full(full),.fifo_empty(empty));
    always #5 clk=~clk;
    task feed;
      input integer a,b,c,d,p,l;
      begin @(negedge clk); old_re=a; old_im=b; fresh_re=c; fresh_im=d;
        sp=p; sl=l; sv=1; @(negedge clk); sv=0; sp=0; sl=0; end
    endtask
    initial begin
      #12 rst=0;
      @(negedge clk); start=1; @(negedge clk); start=0;
      for (i=0;i<N;i=i+1) begin
        // Four pilots deliberately have a slow, positive-real update.  All
        // other carriers are unchanged, so the expected fused stream is
        // exactly the old stream.
        if ((i==0)||(i==50)||(i==100)||(i==150))
          feed(i-80, 0, i-80 + 4, 0, 1, (i==N-1));
        else
          feed(i-80, 0, i-80, 0, 0, (i==N-1));
      end
      count=0; ready=1;
      // Allow the XPM FIFO to drain after the controller's final write.  A
      // fixed bound also protects batch regressions from a bad ready/empty
      // handshake becoming an infinite simulation.
      for (i=0; i<800; i=i+1) begin
        @(posedge clk); #1;
        if (valid) begin
          if (out_im !== 0) $fatal(1,"unexpected imag at %0d: %0d",count,out_im);
          if (count==0 && out_re !== -76) $fatal(1,"out0 %0d",out_re);
          if (count==N-1 && !last) $fatal(1,"missing output last");
          count=count+1;
        end
      end
      $display("END done=%b empty=%b valid=%b full=%b count=%0d",done,empty,valid,full,count);
      if (count != N) $fatal(1,"output count %0d",count);
      $display("PASS Vivado BRAM/FIFO reference, outputs=%0d", count);
      $finish;
    end
endmodule
