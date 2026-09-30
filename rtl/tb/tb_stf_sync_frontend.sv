`timescale 1ns/1ps
module tb_stf_sync_frontend;
    localparam IW=16;
    reg clk=0, rst=1, valid=0;
    reg signed [IW-1:0] re=0, im=0;
    wire mv, hit; wire [31:0] idx;
    wire signed [39:0] cr, ci; wire [39:0] eo,en;
    cofdm_stf_sync_frontend #(.IW(IW),.L(16),.W(64),.SYNC_MIN_RUN(8)) dut(
      .clk,.rst,.sample_valid(valid),.sample_re(re),.sample_im(im),
      .metric_valid(mv),.sync_hit(hit),.sync_index(idx),.corr_re(cr),.corr_im(ci),
      .energy_old(eo),.energy_new(en));
    always #5 clk=~clk;
    integer n, p, hit_count;
    initial begin
      #12 rst=0;
      for (n=0;n<180;n=n+1) begin
        @(negedge clk); valid=1; p=n%16;
        // A deterministic 16-sample complex STF period.
        case (p)
          0: re=1000; 1: re=-1000; 2: re=700; 3: re=-700;
          4: re=400; 5: re=-400; 6: re=900; 7: re=-900;
          8: re=600; 9: re=-600; 10: re=300; 11: re=-300;
          12: re=800; 13: re=-800; 14: re=500; 15: re=-500;
        endcase
        im=0;
      end
      @(negedge clk); valid=0;
      repeat (4) @(posedge clk);
      if (hit_count != 1) $fatal(1,"sync hit count %0d",hit_count);
      $display("PASS STF streaming sync index=%0d corr=%0d",idx,cr);
      $finish;
    end
    always @(posedge clk) begin
      if (hit) begin hit_count=hit_count+1; if (ci!==0) $fatal(1,"imag correlation %0d",ci); end
    end
    initial hit_count=0;
endmodule
