`timescale 1ns/1ps
module tb_pre_ldpc_symbol;
  reg clk=0,rst=1; always #5 clk=~clk;
  reg hv=0,hl=0; reg [7:0] hb=0; reg signed [17:0] hr=0,hi=0;
  reg fv=0,fl=0; reg [7:0] fb=0; reg signed [15:0] yr=0,yi=0; reg ps=0,mode=0;
  reg [23:0] inv=24'd65536;
  wire hready,fready,lv,ll,psv,busy,done,sat; wire [7:0] lb; wire signed [15:0] lr,li; wire signed [31:0] ph;
  cofdm_pre_ldpc_symbol dut(.clk,.rst,.h_load_valid(hv),.h_load_last(hl),.h_load_bin(hb),.h_load_re(hr),.h_load_im(hi),.h_load_ready(hready),
    .fft_valid(fv),.fft_last(fl),.fft_bin(fb),.fft_re(yr),.fft_im(yi),.fft_pilot_sign(ps),.symbol_mode_bpsk(mode),.inv_noise_q16(inv),.fft_ready(fready),
    .llr_valid(lv),.llr_last(ll),.llr_bin(lb),.llr_re(lr),.llr_im(li),.llr_saturated(sat),.phase_valid(psv),.phase(ph),.symbol_done(done),.busy);
  integer k,count,errors; reg saw_phase,saw_done; integer expected_bin;
  function automatic is_pilot(input integer b); begin case(b)
    13,39,65,91,165,191,217,243: is_pilot=1'b1;
    default: is_pilot=1'b0; endcase end endfunction
  function automatic is_data(input integer b); begin
    is_data=((b>=1 && b<=100)||(b>=156)) && !is_pilot(b);
  end endfunction
  function automatic integer next_data(input integer b); integer q; begin
    q=b+1; while(q<256 && !is_data(q)) q=q+1; next_data=q; end endfunction
  initial begin
    #12 rst=0;
    // Load a flat real H=1.0 (Q18.14) on active carriers.
    for(k=1;k<=255;k=k+1) if((k<=100)||(k>=156)) begin
      @(negedge clk); hb=k; hr=18'sd16384; hi=0; hv=1; hl=(k==255); @(posedge clk); #1; hv=0; hl=0;
    end
    // One BPSK header-like symbol, Y is positive real on all active bins.
    for(k=0;k<256;k=k+1) begin
      // Deliberately rotate the whole symbol by +pi/2.  The pilot phase
      // estimator and common-phase LUT must rotate it back before LLR.
      @(negedge clk); fb=k; yr=0; yi=16'sd8192; fl=(k==255); fv=1; ps=0; mode=1; @(posedge clk); #1; fv=0; fl=0;
    end
    count=0; errors=0; saw_phase=0; saw_done=0; expected_bin=1;
    repeat(1200) begin @(posedge clk); #1; if(lv) begin count=count+1; if(lb!==expected_bin[7:0]) begin $display("FAIL LLR bin got=%0d exp=%0d",lb,expected_bin); errors=errors+1; end expected_bin=next_data(expected_bin); if(lr<=0 || li!==0 || sat) errors=errors+1; end if(psv) saw_phase=1; if(done) saw_done=1; end
    if(count!=192 || !saw_phase || !saw_done) begin $display("FAIL pre-LDPC count=%0d phase=%0d done=%0d",count,saw_phase,saw_done); errors=errors+1; end
    if(errors) $fatal(1,"pre-LDPC errors=%0d",errors); $display("PASS pre-LDPC symbol count=%0d",count); $finish;
  end
endmodule
