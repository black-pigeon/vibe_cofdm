`timescale 1ns/1ps
module tb_mid_fusion_ctrl;
    localparam W=8; localparam N=4;
    reg clk=0,rst=1,start=0,sv=0,sl=0,sp=0,fast_unused=0;
    reg signed [W-1:0] orr,ori,fr,fi; reg [W-1:0] ov=1,fv=1;
    wire busy,ovld,olast,done; wire signed [W-1:0] ore,oim; wire [1:0] q; wire fu;
    cofdm_mid_fusion_ctrl #(.W(W),.N_ACTIVE(N),.ACC_W(24)) dut(
      .clk,.rst,.start,.sample_valid(sv),.sample_last(sl),.sample_pilot(sp),
      .old_re(orr),.old_im(ori),.fresh_re(fr),.fresh_im(fi),.old_var(ov),.fresh_var(fv),
      .busy,.out_valid(ovld),.out_last(olast),.out_re(ore),.out_im(oim),.rot_code(q),.fast_update(fu),.done);
    always #5 clk=~clk;
    task feed;
      input integer a,b,c,d; input integer p; input integer last;
      begin @(negedge clk); orr=a;ori=b;fr=c;fi=d;sp=p;sl=last;sv=1; @(negedge clk); sv=0;sp=0;sl=0; end
    endtask
    integer count;
    initial begin
      orr=0;ori=0;fr=0;fi=0; #12 rst=0;
      @(negedge clk); start=1; @(negedge clk); start=0;
      // Pilot samples have fresh=old; correlation is positive real -> q0.
      feed(10,0,10,0,1,0); feed(0,10,0,10,0,0);
      feed(20,0,24,0,1,0); feed(0,20,0,20,0,1);
      count=0;
      while (!done) begin
        @(posedge clk); #1;
        if (ovld) begin
          if (count==0 && (ore!==8'sd10 || oim!==8'sd0)) $fatal(1,"out0 %0d %0d",ore,oim);
          if (count==2 && (ore!==8'sd21 || oim!==8'sd0)) $fatal(1,"out2 %0d %0d",ore,oim);
          if (count==N-1 && !olast) $fatal(1,"missing last");
          count=count+1;
        end
      end
      if (count != N) $fatal(1,"count %0d",count);
      $display("PASS MID fusion controller q=%0d fast=%0d",q,fu); $finish;
    end
endmodule
