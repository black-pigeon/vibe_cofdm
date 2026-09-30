`timescale 1ns/1ps
module tb_sync_frontend_ref_top;
    reg clk=0,rst=1,clear=0,valid=0;
    reg signed [15:0] re=0,im=0; reg signed [31:0] inc=0;
    wire mv,hit,cv; wire [31:0] idx,ph;
    wire signed [15:0] cr,ci;
    wire cfo_v; wire signed [31:0] cfo_angle,cfo_inc;
    cofdm_sync_frontend_ref_top dut(.clk,.rst,.clear_phase(clear),.sample_valid(valid),
      .sample_re(re),.sample_im(im),.phase_inc(inc),.metric_valid(mv),
      .sync_hit(hit),.sync_index(idx),.corrected_valid(cv),.corrected_re(cr),
      .corrected_im(ci),.phase_dbg(ph),.cfo_valid(cfo_v),
      .cfo_angle_turns(cfo_angle),.cfo_phase_inc(cfo_inc));
    always #5 clk=~clk;
    integer n,p,hit_count,out_count,cfo_count;
    initial begin
      #12 rst=0;
      for(n=0;n<180;n=n+1) begin
        @(negedge clk); valid=1; p=n%16;
        case(p)
          0:re=1000;1:re=-1000;2:re=700;3:re=-700;
          4:re=400;5:re=-400;6:re=900;7:re=-900;
          8:re=600;9:re=-600;10:re=300;11:re=-300;
          12:re=800;13:re=-800;14:re=500;15:re=-500;
        endcase
        im=0;
      end
      @(negedge clk); valid=0; repeat(4) @(posedge clk);
      if(hit_count!=1) $fatal(1,"frontend sync hits %0d",hit_count);
      if(out_count!=180) $fatal(1,"frontend output count %0d",out_count);
      if(cfo_count!=1 || cfo_inc > 32'sd1000 || cfo_inc < -32'sd1000)
        $fatal(1,"frontend cfo count=%0d inc=%0d",cfo_count,cfo_inc);
      $display("PASS Vivado sync frontend hit=%0d outputs=%0d cfo=%0d",idx,out_count,cfo_inc);
      $finish;
    end
    always @(posedge clk) begin
      if(hit) hit_count=hit_count+1;
      if(cv) begin out_count=out_count+1; if(cr < -1000 || cr > 1000) $fatal(1,"rotation overflow"); end
      if(cfo_v) cfo_count=cfo_count+1;
    end
    initial begin hit_count=0; out_count=0; cfo_count=0; end
endmodule
