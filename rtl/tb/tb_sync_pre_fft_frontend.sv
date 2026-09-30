`timescale 1ns/1ps
module tb_sync_pre_fft_frontend;
    localparam integer LTF_START=304;
    reg clk=0,rst=1,sv=0; reg signed [15:0] re=0,im=0;
    reg fine_v=0; reg signed [31:0] fine_inc=0;
    reg hdr_v=0,hdr_ok=0,abort=0,done=0;
    wire fi_v,fi_s,busy,rdone,rerr; wire signed [15:0] fi_re,fi_im;
    wire [7:0] sym_i; wire [1:0] sym_k; wire [31:0] rstart;
    wire stf_hit,coarse_v,ltf_v,frame_v; wire [31:0] stf_idx,ltf_idx;
    wire [15:0] ltf_score; wire signed [31:0] phase,coarse_phase;
    reg [7:0] a; wire signed [15:0] tr,ti;
    cofdm_ltf_template_rom rom(.addr(a),.re(tr),.im(ti));
    cofdm_sync_pre_fft_frontend #(.CANDIDATES(5),.SEARCH_RADIUS(2),
      .STF_TO_LTF_USEFUL(192),.SCORE_MIN(16'd8000),.BUFFER_DEPTH(8192),
      .PEAK_TO_BUFFER_OFFSET(9),.DATA_SYMBOLS(1)) dut(
      .clk,.rst,.sample_valid(sv),.sample_re(re),.sample_im(im),
      .fine_valid(fine_v),.fine_phase_inc(fine_inc),.header_crc_valid(hdr_v),
      .header_crc_ok(hdr_ok),.frame_abort(abort),.frame_done(done),
      .fft_in_valid(fi_v),.fft_in_ready(1'b1),.fft_in_re(fi_re),.fft_in_im(fi_im),
      .fft_symbol_start(fi_s),.fft_symbol_index(sym_i),.fft_symbol_kind(sym_k),
      .replay_busy(busy),.replay_done(rdone),.replay_error(rerr),
      .replay_start_index(rstart),.corrected_valid(),.corrected_re(),.corrected_im(),
      .stf_candidate(stf_hit),.stf_index(stf_idx),.coarse_valid(coarse_v),
      .coarse_phase_inc(coarse_phase),.phase_inc(phase),.coarse_locked(),.fine_locked(),
      .ltf_peak_valid(ltf_v),.ltf_peak_score(ltf_score),.ltf_peak_index(ltf_idx),
      .frame_start(),.frame_valid(frame_v),.capture_locked(),.capture_timeout(),
      .false_alarm_count(),.capture_state());
    always #5 clk=~clk;
    integer n,count,starts; reg saw_ltf=0,saw_done=0; reg ltf_d=0,fine_en_d=0;
    always @(negedge clk) begin
      if (rst) begin sv<=0; fine_v<=0; hdr_v<=0; end else begin
        sv <= (n<7000); im<=0;
        if (n>=LTF_START && n<LTF_START+256) begin a=n-LTF_START; re<=tr; end
        else case(n%16)
          0:re<=1000; 1:re<=-1000; 2:re<=700; 3:re<=-700;
          4:re<=400; 5:re<=-400; 6:re<=900; 7:re<=-900;
          8:re<=600; 9:re<=-600; 10:re<=300; 11:re<=-300;
          12:re<=800; 13:re<=-800; 14:re<=500; default:re<=-500;
        endcase
        n<=n+1;
        // Model the downstream fine-CFO and header decisions with the same
        // two-cycle event alignment used by the closed-loop smoke test.
        fine_v<=ltf_d; ltf_d<=ltf_v; hdr_v<=fine_en_d; hdr_ok<=fine_en_d;
        fine_en_d<=fine_v;
      end
    end
    always @(posedge clk) begin
      if (stf_hit) $display("pre STF idx=%0d n=%0d",stf_idx,n);
      if (ltf_v) begin saw_ltf<=1; $display("pre LTF idx=%0d score=%0d n=%0d",ltf_idx,ltf_score,n); end
      if (rdone) saw_done<=1;
      if (fi_v) begin
        count<=count+1;
        if (fi_s) starts<=starts+1;
      end
    end
    initial begin
      n=0; count=0; starts=0; #12 rst=0;
      repeat(10000) @(posedge clk);
      if (!saw_ltf || !saw_done || rerr || count!=864 || starts!=3)
        $fatal(1,"pre-FFT failed ltf=%0d done=%0d err=%0d count=%0d starts=%0d",saw_ltf,saw_done,rerr,count,starts);
      $display("PASS unified pre-FFT frontend count=%0d starts=%0d replay_start=%0d",count,starts,rstart);
      $finish;
    end
endmodule
