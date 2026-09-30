`timescale 1ns/1ps
// End-to-end acquisition smoke test.  The STF detector creates the candidate
// from a repeated 16-sample sequence; the top then corrects the stream with
// the coarse NCO and finds a known LTF in the scheduled window.  Fine CFO and
// header CRC are supplied as the next PHY stages would supply them.
module tb_sync_ltf_cfo_top;
    integer ltf_start_cfg;
    // The STF metric is a pipelined decision (the event occurs at input
    // sample 116 while its reported index is 102), so the scheduler's
    // useful offset is measured from the event, not the reported index.
    reg clk=0, rst=1, sample_valid=0;
    reg signed [15:0] sample_re=0, sample_im=0;
    reg fine_valid=0; reg signed [31:0] fine_inc=0;
    reg hdr_valid=0, hdr_ok=0, frame_abort=0, frame_done=0;
    reg fine_enable_d=0, ltf_valid_d=0;
    wire metric_valid, stf_candidate, coarse_valid, clear_phase;
    wire signed [31:0] coarse_inc, phase_inc;
    wire [31:0] stf_index, aligned_index, ltf_index;
    wire signed [15:0] corrected_re, corrected_im;
    wire corrected_valid, aligned_hit, ltf_valid, busy, pending, error;
    wire [15:0] ltf_score;
    wire signed [47:0] ltf_cr, ltf_ci; wire [47:0] ltf_energy;
    wire frame_start, frame_valid, locked, timeout;
    wire [31:0] false_count, frame_idx, ltf_start_idx;
    wire [2:0] cap_state;
    wire candidate_valid, coarse_enable, ltf_start_evt, fine_enable, header_enable;
    wire signed [31:0] stf_angle; wire [39:0] eold,enew; wire angle_busy;
    reg [7:0] rom_addr; wire signed [15:0] rom_re,rom_im;
    cofdm_ltf_template_rom rom(.addr(rom_addr),.re(rom_re),.im(rom_im));

    cofdm_sync_ltf_cfo_top #(.CANDIDATES(5),.SEARCH_RADIUS(2),
      .STF_TO_LTF_USEFUL(192),.SCORE_MIN(16'd8000),
      .CAP_LTF_MIN_OFFSET(64),.CAP_LTF_MAX_OFFSET(384),
      .CAP_LTF_TIMEOUT(20000),.CAP_FINE_TIMEOUT(32),
      .CAP_HEADER_TIMEOUT(32),.CAP_HOLDOFF(16)) dut (
      .clk,.rst,.sample_valid,.sample_re,.sample_im,.fine_valid,
      .fine_phase_inc(fine_inc),.header_crc_valid(hdr_valid),
      .header_crc_ok(hdr_ok),.frame_abort,.frame_done,
      .fft_out_valid(1'b0),.fft_out_last(1'b0),.fft_out_re(16'sd0),
      .fft_out_im(16'sd0),.fft_rot_re(16'sd0),.fft_rot_im(16'sd0),
      .metric_valid,.stf_candidate,.stf_index,.coarse_valid,
      .coarse_phase_inc(coarse_inc),.phase_inc,.clear_phase,
      .coarse_locked(),.fine_locked(),.corrected_valid,.corrected_re,
      .corrected_im,.phase_dbg(),.aligned_stf_candidate(aligned_hit),
      .aligned_stf_index(aligned_index),.ltf_peak_valid(ltf_valid),
      .ltf_peak_score(ltf_score),.ltf_peak_index(ltf_index),
      .ltf_peak_corr_re(ltf_cr),.ltf_peak_corr_im(ltf_ci),
      .ltf_peak_energy(ltf_energy),.ltf_search_busy(busy),
      .ltf_search_pending(pending),.ltf_search_error(error),
      .frame_start,.frame_valid,.capture_locked(locked),
      .capture_timeout(timeout),.false_alarm_count(false_count),
      .frame_start_index(frame_idx),.ltf_start_index(ltf_start_idx),
      .capture_state(cap_state),.candidate_valid,.coarse_cfo_enable(coarse_enable),
      .ltf_start(ltf_start_evt),.fine_cfo_enable(fine_enable),
      .header_enable,.stf_angle_turns(stf_angle),
      .stf_energy_old(eold),.stf_energy_new(enew),.cfo_angle_busy(angle_busy));
    always #5 clk=~clk;

    integer n, wait_n; reg saw_stf=0,saw_coarse=0,saw_ltf=0,saw_frame=0;
    reg last_busy=0,last_pending=0;
    // Drive one accepted sample per cycle.  The LTF starts at the nominal
    // location; the matcher searches around it to tolerate timing error.
    always @(negedge clk) begin
      if (rst) begin sample_valid<=0; sample_re<=0; sample_im<=0; rom_addr<=0; end
      else begin
        sample_valid<=1; sample_im<=0;
        if (n >= ltf_start_cfg && n < ltf_start_cfg+256) begin
          rom_addr = n-ltf_start_cfg; sample_re <= rom_re;
        end else begin
          rom_addr = 0;
          case (n % 16)
            0: sample_re<=1000; 1: sample_re<=-1000; 2: sample_re<=700; 3: sample_re<=-700;
            4: sample_re<=400; 5: sample_re<=-400; 6: sample_re<=900; 7: sample_re<=-900;
            8: sample_re<=600; 9: sample_re<=-600; 10: sample_re<=300; 11: sample_re<=-300;
            12: sample_re<=800; 13: sample_re<=-800; 14: sample_re<=500; default: sample_re<=-500;
          endcase
        end
        n <= n+1;
        // The capture FSM consumes fine CFO and header events after the LTF
        // result; these pulses model the downstream FFT/CFO/header blocks.
        fine_valid <= ltf_valid_d;
        ltf_valid_d <= ltf_valid;
        hdr_valid <= fine_enable_d;
        hdr_ok <= fine_enable_d;
        fine_enable_d <= fine_enable;
      end
    end
    always @(posedge clk) begin
      if (stf_candidate) begin saw_stf<=1; $display("STF candidate idx=%0d",stf_index); end
      if (coarse_valid) begin saw_coarse<=1; $display("coarse inc=%0d angle=%0d",coarse_inc,stf_angle); end
      if (aligned_hit) $display("aligned STF idx=%0d",aligned_index);
      if (busy != last_busy) $display("LTF busy=%0d at n=%0d",busy,n);
      if (pending != last_pending) $display("LTF pending=%0d at n=%0d",pending,n);
      last_busy <= busy; last_pending <= pending;
      if (candidate_valid) $display("capture candidate idx=%0d",aligned_index);
      if (ltf_start_evt) $display("capture LTF start idx=%0d",ltf_index);
      if (ltf_valid) begin saw_ltf<=1; $display("LTF peak idx=%0d score=%0d",ltf_index,ltf_score); end
      if (fine_enable || fine_valid || hdr_valid || frame_start || frame_valid)
        $display("capture state=%0d fine_en=%0d fine_v=%0d hdr_v=%0d frame_s=%0d frame_v=%0d",cap_state,fine_enable,fine_valid,hdr_valid,frame_start,frame_valid);
      if (frame_valid) begin saw_frame<=1; $display("FRAME valid idx=%0d",frame_idx); end
    end
    initial begin
      n=0; ltf_start_cfg=304; if (!$value$plusargs("LTF_START=%d",ltf_start_cfg)) ltf_start_cfg=304; #12 rst=0;
      repeat (900) @(posedge clk);
      wait_n=0; while (!saw_ltf && wait_n<30000) begin @(posedge clk); wait_n=wait_n+1; end
      if (!saw_stf || !saw_coarse || !saw_ltf || error)
        $fatal(1,"acquisition failed stf=%0d coarse=%0d ltf=%0d err=%0d",saw_stf,saw_coarse,saw_ltf,error);
      repeat (20) @(posedge clk);
      if (!saw_frame) $fatal(1,"header/capture did not lock");
      $display("PASS closed-loop STF/CFO/LTF/capture top");
      $finish;
    end
endmodule
