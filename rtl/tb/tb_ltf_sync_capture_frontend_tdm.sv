`timescale 1ns/1ps
module tb_ltf_sync_capture_frontend_tdm;
    reg clk=0,rst=1,valid=0,hit=0;
    reg signed [15:0] re=0,im=0; reg [31:0] idx=100;
    wire pv; wire [15:0] score; wire [31:0] pidx; wire busy,pending,error;
    wire signed [47:0] cr,ci; wire [47:0] en;
    reg [7:0] a; wire signed [15:0] tr,ti; integer n,wait_cycles;
    cofdm_ltf_template_rom rom(.addr(a),.re(tr),.im(ti));
    cofdm_ltf_sync_capture_frontend #(
      .CANDIDATES(5),.MATCHER_TDM(1),.STF_TO_LTF_USEFUL(12),
      .SEARCH_RADIUS(2),.SCORE_MIN(16'd30000)
    ) dut(
      .clk,.rst,.sample_valid(valid),.sample_re(re),.sample_im(im),
      .stf_hit(hit),.stf_index(idx),.ltf_peak_valid(pv),
      .ltf_peak_score(score),.ltf_peak_index(pidx),.ltf_peak_corr_re(cr),
      .ltf_peak_corr_im(ci),.ltf_peak_energy(en),.ltf_search_busy(busy),
      .ltf_search_pending(pending),.ltf_search_error(error));
    always #5 clk=~clk;
    task send(input signed [15:0] xr,input signed [15:0] xi,input h);
      begin @(negedge clk); valid=1; re=xr; im=xi; hit=h;
        @(posedge clk); #1; valid=0; hit=0; end
    endtask
    reg seen=0; reg [31:0] seen_idx; reg [15:0] seen_score;
    always @(posedge clk) if(pv) begin
      seen=1; seen_idx=pidx; seen_score=score;
      $display("TDM XSim peak idx=%0d score=%0d",pidx,score);
    end
    initial begin
      #12 rst=0;
      send(0,0,1);
      for(n=1;n<280;n=n+1) begin
        if(n>=11 && n<267) begin a=n-11; #1; send(tr,ti,0); end
        else send(0,0,0);
      end
      wait_cycles=0;
      while(!seen && wait_cycles<6000) begin @(posedge clk); wait_cycles=wait_cycles+1; end
      if(!seen || seen_idx!=110 || seen_score<30000 || error)
        $fatal(1,"TDM integrated matcher failure seen=%0d idx=%0d score=%0d err=%0d",seen,seen_idx,seen_score,error);
      $display("PASS TDM integrated LTF sync frontend idx=%0d score=%0d",seen_idx,seen_score);
      $finish;
    end
endmodule
