`timescale 1ns/1ps
module tb_pre_fft_replay;
    localparam NFFT=8, CP=2, TRAIN=2, DATA=1, TOTAL=(NFFT+CP)*(TRAIN+DATA);
    reg clk=0,rst=1,v=0,peak=0,ready=1; reg signed [15:0] re=0,im=0; reg [31:0] pidx=0;
    wire ov,ss,busy,done,err; wire signed [15:0] ore,oim; wire [7:0] si; wire [1:0] sk; wire [31:0] start;
    cofdm_pre_fft_replay #(.NFFT(NFFT),.CP_LEN(CP),.TRAINING_SYMBOLS(TRAIN),
      .DATA_SYMBOLS(DATA),.BUFFER_DEPTH(1024)) dut(
      .clk,.rst,.sample_valid(v),.sample_re(re),.sample_im(im),.peak_valid(peak),
      .peak_index(pidx),.out_valid(ov),.out_ready(ready),.out_re(ore),.out_im(oim),
      .out_symbol_start(ss),.out_symbol_index(si),.out_symbol_kind(sk),
      .replay_busy(busy),.replay_done(done),.replay_error(err),.replay_start_index(start));
    always #5 clk=~clk;
    integer n,count,starts; reg saw_done;
    always @(negedge clk) begin
      if (rst) begin v<=0; peak<=0; end else begin
        v<=1; re<=n; im<=-n; peak<=(n==700); pidx<=500;
        n<=n+1;
      end
    end
    always @(posedge clk) if(ov && ready) begin
      if (ore !== (500-CP+count) || oim !== -(500-CP+count))
        $fatal(1,"sample count=%0d re=%0d im=%0d",count,ore,oim);
      if (ss) starts=starts+1;
      count=count+1;
    end
    always @(posedge clk) if (done) saw_done=1;
    initial begin
      n=0; count=0; starts=0; saw_done=0; #12 rst=0;
      repeat(850) @(posedge clk);
      if(count!=TOTAL || starts!=TRAIN+DATA || !saw_done || err)
        $fatal(1,"replay count=%0d starts=%0d done=%0d err=%0d",count,starts,saw_done,err);
      $display("PASS pre-FFT replay count=%0d starts=%0d start_idx=%0d",count,starts,start);
      $finish;
    end
endmodule
