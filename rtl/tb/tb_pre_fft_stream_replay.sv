`timescale 1ns/1ps
module tb_pre_fft_stream_replay;
  // Deliberately stream more samples than the ring can hold.  This is the
  // property that distinguishes the bounded replay from the old full-frame
  // capture implementation.
  localparam integer SPAN=10, SYMBOLS=1000, TOTAL=SPAN*SYMBOLS;
  reg clk=0,rst=1,v=0,start=0,ready=1; reg signed [15:0] re=0,im=0;
  reg [31:0] start_idx=0; reg [15:0] symbols=3;
  reg extend_valid=0;
  wire ov,ss,busy,done,err; wire signed [15:0] ore,oim; wire [15:0] si;
  cofdm_pre_fft_stream_replay #(.NFFT(8),.CP_LEN(2),.BUFFER_DEPTH(2048),
    .SYMBOL_INDEX_W(16)) dut(
    .clk,.rst,.sample_valid(v),.sample_re(re),.sample_im(im),
    .replay_start(start),.replay_start_index(start_idx),
    .replay_symbol_count(symbols),.replay_extend_valid(extend_valid),
    .out_valid(ov),.out_ready(ready),
    .out_re(ore),.out_im(oim),.out_symbol_start(ss),.out_symbol_index(si),
    .replay_busy(busy),.replay_done(done),.replay_error(err));
  always #5 clk=~clk;
  integer n,count,starts; reg saw_done;
  always @(negedge clk) begin
    if (rst) begin v<=0; start<=0; end
    else begin
      v<=1; re<=n; im<=-n; start<=(n==2000); start_idx<=100;
      // Mimic a PHY header decoder extending the initial LTF/header replay
      // after the stream has already started.
      extend_valid <= (n==2010);
      if (n==2010) symbols <= SYMBOLS;
      n<=n+1;
    end
  end
  always @(posedge clk) begin
    if (ov && ready) begin
      if (ore !== (100+count) || oim !== -(100+count)) $fatal(1,"offset=%0d re=%0d",count,ore);
      if (ss && si !== (count/10)) $fatal(1,"symbol index=%0d expected=%0d",si,count/10);
      if (ss) starts<=starts+1; count<=count+1;
    end
    if (done) saw_done<=1;
  end
  initial begin n=0;count=0;starts=0;saw_done=0;#12 rst=0;
    repeat(32000) @(posedge clk);
    if (count!=TOTAL || starts!=SYMBOLS || !saw_done || err)
      $fatal(1,"long replay count=%0d starts=%0d done=%0d err=%0d",count,starts,saw_done,err);
    $display("PASS bounded stream replay symbols=%0d samples=%0d",SYMBOLS,count);$finish;
  end
endmodule
