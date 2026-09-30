`timescale 1ns/1ps
module tb_capture_ctrl;
    reg clk=0, rst=1, valid=0;
    reg stf_hit=0, ltf_v=0, fine_v=0, hdr_v=0, hdr_ok=0, abort=0, done=0;
    reg [31:0] stf_idx=0, ltf_idx=0;
    reg [15:0] ltf_score=0;
    wire candidate, coarse_en, ltf_start, fine_en, hdr_en, frame_start, frame_valid;
    wire locked, timeout; wire [31:0] false_count, frame_idx, ltf_out_idx; wire [2:0] state;
    cofdm_capture_ctrl #(.SCORE_W(16),.TIMER_W(8),.LTF_SCORE_MIN(16'd7864),
      .LTF_MIN_OFFSET(64),.LTF_MAX_OFFSET(384),.LTF_TO_FRAME_OFFSET(192),
      .LTF_TIMEOUT(16),.FINE_TIMEOUT(8),.HEADER_TIMEOUT(12),.HOLDOFF(3),.LOCK_TIMEOUT(100)) dut(
      .clk,.rst,.sample_valid(valid),.stf_hit,.stf_index(stf_idx),
      .ltf_peak_valid(ltf_v),.ltf_peak_score(ltf_score),.ltf_peak_index(ltf_idx),
      .fine_cfo_valid(fine_v),.header_crc_valid(hdr_v),.header_crc_ok(hdr_ok),
      .frame_abort(abort),.frame_done(done),.candidate_valid(candidate),
      .coarse_cfo_enable(coarse_en),.ltf_start,.fine_cfo_enable(fine_en),
      .header_enable(hdr_en),.frame_start,.frame_valid,.capture_locked(locked),
      .capture_timeout(timeout),.false_alarm_count(false_count),
      .frame_start_index(frame_idx),.ltf_start_index(ltf_out_idx),.state_dbg(state));
    always #5 clk=~clk;
    integer candidates, ltf_accepts, valids, timeouts;

    task tick;
      input t_stf, t_ltf, t_fine, t_hdr_v, t_hdr_ok, t_done;
      input [31:0] t_stf_idx, t_ltf_idx;
      input [15:0] t_score;
      begin
        @(negedge clk); valid=1; stf_hit=t_stf; ltf_v=t_ltf; fine_v=t_fine;
        hdr_v=t_hdr_v; hdr_ok=t_hdr_ok; done=t_done; stf_idx=t_stf_idx;
        ltf_idx=t_ltf_idx; ltf_score=t_score;
        @(posedge clk);
        #1;
        stf_hit=0; ltf_v=0; fine_v=0; hdr_v=0; hdr_ok=0; done=0;
      end
    endtask
    initial begin
      #12 rst=0;
      // Normal candidate, LTF, fine CFO, and valid header.
      tick(1,0,0,0,0,0,100,0,0);
      repeat(4) tick(0,0,0,0,0,0,0,0,0);
      tick(0,1,0,0,0,0,0,292,16'd50000);
      tick(0,0,1,0,0,0,0,0,0);
      tick(0,0,0,1,1,0,0,0,0);
      tick(0,0,0,0,0,0,0,0,0);
      if (candidates!=1 || ltf_accepts!=1 || valids!=1 || locked!==1)
        $fatal(1,"normal capture c=%0d l=%0d v=%0d locked=%0d",candidates,ltf_accepts,valids,locked);
      tick(0,0,0,0,0,1,0,0,0);
      repeat(4) tick(0,0,0,0,0,0,0,0,0);

      // STF-only false candidate: timeout, no valid frame.
      tick(1,0,0,0,0,0,500,0,0);
      repeat(18) tick(0,0,0,0,0,0,0,0,0);
      if (timeouts<1 || valids!=1 || false_count<1)
        $fatal(1,"STF-only timeout=%0d valid=%0d false=%0d",timeouts,valids,false_count);
      repeat(4) tick(0,0,0,0,0,0,0,0,0);

      // Candidate with weak/illegal LTF is rejected immediately.
      tick(1,0,0,0,0,0,800,0,0);
      repeat(2) tick(0,0,0,0,0,0,0,0,0);
      tick(0,1,0,0,0,0,0,820,16'd10);
      if (false_count<2 || valids!=1)
        $fatal(1,"weak LTF false=%0d valid=%0d",false_count,valids);
      $display("PASS capture controller candidates=%0d ltf=%0d valid=%0d timeout=%0d false=%0d",
        candidates,ltf_accepts,valids,timeouts,false_count);
      $finish;
    end
    initial begin candidates=0; ltf_accepts=0; valids=0; timeouts=0; end
    always @(posedge clk) begin
      #1;
      if (candidate) candidates=candidates+1;
      if (ltf_start) begin
        ltf_accepts=ltf_accepts+1;
        if (frame_idx!==100 || ltf_out_idx!==292) $fatal(1,"index mismatch");
      end
      if (frame_valid) valids=valids+1;
      if (timeout) timeouts=timeouts+1;
    end
endmodule
