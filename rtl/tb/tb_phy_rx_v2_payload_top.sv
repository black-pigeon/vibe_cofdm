`timescale 1ns/1ps
module tb_phy_rx_v2_payload_top;
  integer fd, sign_errors=0, zero_llrs=0, high_water=0;
  reg test_done=0;
  reg clk=0; always #4.069 clk=~clk;
  reg rst=1, sample_valid=0;
  reg signed [15:0] sample_re=0, sample_im=0;
  reg payload_byte_ready=1;
  wire payload_byte_valid, payload_byte_last, payload_frame_done, payload_frame_error;
  wire [7:0] payload_byte;
  wire payload_llr_valid, payload_llr_last;
  wire signed [15:0] payload_llr;
  wire [11:0] header_payload_bytes;
  wire header_valid, header_ok;
  reg [31:0] iq[0:65535], cfg[0:4];
  integer n, count=0, cycles=0;
  reg test_pass=0;
  reg bits[0:33047]; integer llr_count=0;

  cofdm_phy_rx_v2_payload_top dut(
    .clk,.rst,.sample_valid,.sample_re(sample_re),.sample_im(sample_im),
    .inv_noise_q16(24'hffffff),.payload_byte_ready,
    .payload_byte_valid,.payload_byte,.payload_byte_last,
    .payload_frame_done,.payload_frame_error,
    .payload_crc_ok(),.payload_padding_ok(),.payload_ldpc_ok(),
    .payload_backend_busy(),.payload_decoder_iterations(),.payload_codeword_index(),
    .payload_start_rejected(),.payload_llr_valid,.payload_llr_last,
    .payload_llr_cw_first(),.payload_llr_cw_last(),.payload_llr,
    .header_valid,.header_ok,.header_crc_ok(),.header_payload_bytes,
    .header_scrambler_seed(),.header_midamble_code(),.header_error(),.header_busy(),
    .frame_valid(),.capture_locked(),.capture_timeout(),.false_alarm_count(),
    .replay_busy(),.replay_done(),.replay_error(),.fft_overflow(),
    .phy_frame_done(),.phy_frame_error(),.state_dbg(),.fine_valid(),.fine_phase_inc());

  always @(negedge clk) begin
    cycles=cycles+1;
    payload_byte_ready=(cycles%19<13);
  end

  always @(posedge clk) if(!rst) begin
    if(dut.payload.wr_idx-dut.payload.rd_idx>high_water) high_water=dut.payload.wr_idx-dut.payload.rd_idx;
    if(header_valid) $display("Header ok=%b bytes=%0d time=%t",header_ok,header_payload_bytes,$time);
    if(payload_llr_valid) begin
      if(llr_count>=cfg[1]) $fatal(1,"Excess LLR");
      if(payload_llr==0) zero_llrs=zero_llrs+1;
      if(payload_llr[15] !== bits[llr_count]) sign_errors=sign_errors+1;
      $fdisplay(fd,"%0d",payload_llr);
      if(llr_count<4) $display("LLR[%0d]=%0d",llr_count,payload_llr);
      llr_count=llr_count+1;
    end
    if(dut.phy_frame_error || dut.capture_timeout || dut.payload_start_rejected)
      $fatal(1,"PHY/capture/admission error state=%d",dut.phy.state);
    if(dut.payload.bridge.codeword_done) $display("Decoded CW=%0d ok=%b iterations=%0d",dut.payload_codeword_index,dut.payload_ldpc_ok,dut.payload_decoder_iterations);
    if(payload_frame_error) begin
      $display("Payload backend error state=%d post=%b bridge=%b crc=%b pad=%b ldpc=%b bits=%d cw=%d",
        dut.payload.state,dut.payload.post_error,dut.payload.br_error,
        dut.payload_crc_ok,dut.payload_padding_ok,dut.payload_ldpc_ok,
        dut.payload.post.bit_count,dut.payload.post.cw_count);
      test_done=1; $fclose(fd); $finish;
    end
    if(payload_byte_valid && payload_byte_ready) begin
      if(count>=cfg[2] || payload_byte!==count[7:0] ||
         payload_byte_last!==(count==cfg[2]-1))
        $fatal(1,"byte %0d got=%h last=%b",count,payload_byte,payload_byte_last);
      count=count+1;
    end
    if(payload_frame_done) begin
      if(count!=cfg[2]) $fatal(1,"done count=%0d len=%0d",count,cfg[2]);
      $display("PASS actual IQ -> PHY -> Payload LDPC -> CRC32 -> %0d bytes",count);
      if(llr_count!=cfg[1] || !dut.payload_crc_ok || !dut.payload_ldpc_ok || !dut.payload_padding_ok)
        $fatal(1,"Incomplete or unverified frame");
      $display("METRICS cycles=%0d llrs=%0d sign_errors=%0d zeros=%0d max_pending_llrs=%0d",cycles,llr_count,sign_errors,zero_llrs,high_water);
      test_pass=1; test_done=1; $fclose(fd);
      $finish;
    end
  end

  initial begin
    // Vivado exports the .mem files into the XSim run directory.
    // Vector files are copied into the XSim working directory by the Tcl
    // launcher. Keeping a plain relative path avoids simulator-specific
    // dynamic-string plusarg behavior.
    fd=$fopen("rtl_llr.txt","w"); if(!fd) $fatal(1,"LLR output open failed");
    $readmemh("rx_config.mem",cfg);
    if(^cfg[0]===1'bx || cfg[0]==0 || cfg[0]>65536) $fatal(1,"missing/invalid vector config");
    $readmemh("rx_bits.mem",bits,0,cfg[1]-1);
    $readmemh("rx_iq.mem",iq,0,cfg[0]-1);
    repeat(16) @(negedge clk); rst=0;
    for(n=0;n<cfg[0];n=n+1) begin
      sample_valid=1; {sample_im,sample_re}=iq[n]; @(negedge clk);
      sample_valid=0; repeat(7) @(negedge clk);
    end
    repeat(16000000) @(negedge clk);
    $fatal(1,"Payload timeout state=%d bytes=%0d header=%b/%b",dut.phy.state,count,header_valid,header_ok);
  end
  initial begin
    #1000000;
    $display("Progress t=%t PHY=%d payload=%d wr=%d rd=%d decoder=%d",$time,dut.phy.state,dut.payload.state,dut.payload.wr_idx,dut.payload.rd_idx,dut.payload.bridge.decoder.state);
  end
endmodule
