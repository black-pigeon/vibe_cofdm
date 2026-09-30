`timescale 1ns/1ps
module tb_fft_stream_frontend;
    reg clk=0, resetn=0, valid=0, sym_start=0;
    reg signed [15:0] re=0, im=0;
    wire ready, ov, ol, od, started, overflow, ihalt, ohalt, cfg_done;
    wire signed [15:0] ore, oim; wire [7:0] ouser; wire [31:0] accepted;
    cofdm_fft_stream_frontend dut(
      .aclk(clk),.aresetn(resetn),.in_valid(valid),.in_ready(ready),
      .in_symbol_start(sym_start),.in_re(re),.in_im(im),.out_valid(ov),
      .out_ready(1'b1),.out_re(ore),.out_im(oim),.out_last(ol),
      .out_user(ouser),.frame_started(started),.fft_overflow(overflow),
      .input_halt(ihalt),.output_halt(ohalt),.config_done(cfg_done),
      .accepted_fft_samples(accepted));
    always #4.069 clk=~clk;
    integer n, out_count, last_count;
    initial begin
      repeat (5) @(posedge clk); resetn=1;
      // First symbol: 32 CP samples followed by 256 useful samples.
      for (n=0; n<288; n=n+1) begin
        while (!ready) @(posedge clk);
        @(negedge clk); valid=1; sym_start=(n==0);
        // A deterministic complex impulse in the useful part.
        if (n==32) begin re=16'sd12000; im=16'sd0; end
        else begin re=16'sd0; im=16'sd0; end
        @(posedge clk); #1; valid=0; sym_start=0;
      end
      // The configured non-realtime XFFT may insert bubbles between output
      // beats; allow enough wall-clock cycles for all 256 results.
      repeat (1800) @(posedge clk);
      if (out_count != 256 || last_count != 1)
        $fatal(1,"FFT stream count=%0d last=%0d accepted=%0d",out_count,last_count,accepted);
      if (accepted != 256) $fatal(1,"FFT accepted samples=%0d",accepted);
      $display("PASS XFFT 256 CP removal outputs=%0d last=%0d overflow=%0d",out_count,last_count,overflow);
      $finish;
    end
    initial begin out_count=0; last_count=0; end
    always @(posedge clk) begin
      #1;
      if (ov) begin
        out_count=out_count+1;
        if (out_count<=4 || ol) $display("FFT out %0d t=%0t last=%0d re=%0d im=%0d",out_count,$time,ol,ore,oim);
        if (ol) last_count=last_count+1;
      end
    end
endmodule
