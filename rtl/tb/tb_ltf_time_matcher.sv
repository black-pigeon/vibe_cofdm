`timescale 1ns/1ps
module tb_ltf_time_matcher;
    reg clk=0,rst=1,valid=0,start=0; reg signed [15:0] re=0,im=0;
    reg [31:0] base=1000; wire ready,busy,pvalid,error; wire [15:0] score; wire [31:0] index; wire [47:0] energy;
    wire signed [47:0] cre,cim;
    cofdm_ltf_time_matcher #(.CANDIDATES(5)) dut(.clk,.rst,.sample_valid(valid),
      .sample_re(re),.sample_im(im),.search_start(start),.search_base_index(base),
      .search_ready(ready),.search_busy(busy),.peak_valid(pvalid),.peak_score(score),
      .peak_index(index),.peak_corr_re(cre),.peak_corr_im(cim),.peak_energy(energy),.search_error(error));
    always #5 clk=~clk;
    integer k; reg [15:0] got_score; reg [31:0] got_index; reg seen=0;
    reg [7:0] rom_addr; wire signed [15:0] tre,tim;
    cofdm_ltf_template_rom rom(.addr(rom_addr),.re(tre),.im(tim));
    task send(input signed [15:0] r,input signed [15:0] x,input st);
      begin @(negedge clk); valid=1; re=r; im=x; start=st; @(posedge clk); #1 valid=0; start=0; end
    endtask
    always @(posedge clk) if(pvalid) begin seen=1; got_score=score; got_index=index; $display("corr=%0d+j%0d energy=%0d",cre,cim,energy); end
    initial begin
      #12 rst=0;
      // Marker is presented one cycle before the first search sample.
      @(negedge clk); start=1; valid=0; @(posedge clk); #1 start=0;
      for(k=0;k<260;k=k+1) begin
        if(k>=2 && k<258) begin rom_addr=k-2; #1; send(tre,tim,0); end
        else send(0,0,0);
      end
      repeat(4) @(posedge clk);
      if(!seen || got_index!=1002 || got_score==0 || error) $fatal(1,"matcher failure seen=%0d idx=%0d score=%0d err=%0d",seen,got_index,got_score,error);
      $display("PASS LTF time matcher idx=%0d score=%0d",got_index,got_score); $finish;
    end
endmodule
