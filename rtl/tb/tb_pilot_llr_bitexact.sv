`timescale 1ns/1ps
module tb_pilot_llr_bitexact;
  parameter VEC_DIR="matlab/vectors/pilot_llr";
  localparam integer N=96;
  reg clk=0, rst=1, in_valid=0, mode=0;
  reg signed [15:0] yr,yi;
  reg signed [17:0] hr,hi;
  reg [23:0] inv;
  wire in_ready, out_valid, out_last, saturated;
  wire signed [15:0] lr,li;
  reg signed [15:0] yrv[0:N-1],yiv[0:N-1],lre[0:N-1],lie[0:N-1];
  reg signed [17:0] hrv[0:N-1],hiv[0:N-1];
  reg [23:0] invv[0:N-1]; reg [0:0] modev[0:N-1],satv[0:N-1];
  cofdm_matched_llr dut(.clk,.rst,.in_valid,.mode_bpsk(mode),.y_re(yr),.y_im(yi),
    .h_re(hr),.h_im(hi),.inv_noise_q16(inv),.in_ready,.out_valid,.out_last,
    .llr_re(lr),.llr_im(li),.saturated);
  always #5 clk=~clk;
  integer k,errors; integer got;
  always @(posedge clk) begin
    #1;
    if(out_valid) begin
      if(got>=N || lr!==lre[got] ||
         (!modev[got] && li!==lie[got]) || (modev[got] && li!==0) || !out_last) begin
        $display("FAIL idx=%0d mode=%0d got=(%0d,%0d) exp=(%0d,%0d)",got,modev[got],lr,li,lre[got],lie[got]); errors=errors+1;
      end
      got=got+1;
    end
  end
  initial begin
    $readmemh({VEC_DIR,"/y_re.hex"},yrv); $readmemh({VEC_DIR,"/y_im.hex"},yiv);
    $readmemh({VEC_DIR,"/h_re.hex"},hrv); $readmemh({VEC_DIR,"/h_im.hex"},hiv);
    $readmemh({VEC_DIR,"/inv_noise.hex"},invv); $readmemh({VEC_DIR,"/mode_bpsk.hex"},modev);
    $readmemh({VEC_DIR,"/expected_re.hex"},lre); $readmemh({VEC_DIR,"/expected_im.hex"},lie);
    $readmemh({VEC_DIR,"/expected_sat.hex"},satv);
    errors=0; got=0; #12 rst=0;
    for(k=0;k<N;k=k+1) begin
      @(negedge clk); yr=yrv[k]; yi=yiv[k]; hr=hrv[k]; hi=hiv[k]; inv=invv[k]; mode=modev[k]; in_valid=1;
      @(posedge clk); #1; in_valid=0;
    end
    repeat(5) @(posedge clk);
    if(got!=N) begin $display("FAIL output count=%0d exp=%0d",got,N); errors=errors+1; end
    if(errors!=0) $fatal(1,"pilot/LLR bit-exact errors=%0d",errors);
    $display("PASS pilot/LLR bit-exact vectors=%0d",got); $finish;
  end
endmodule
