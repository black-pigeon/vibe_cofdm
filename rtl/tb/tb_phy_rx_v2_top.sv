`timescale 1ns/1ps
module tb_phy_rx_v2_top;
  reg clk=0;always #4.069 clk=~clk;
  reg rst=1,sv=0;reg signed [15:0] x=0,y=0;
  wire pv,pl,cf,cl,hv,hok,crc,herr,hbusy,valid,locked,to,rb,rd,re,overflow,done,err,fine_v;
  wire signed [15:0] llr;wire [11:0] len;wire [6:0] seed;wire [1:0] mid;
  wire [31:0] false_count;wire [4:0] state;wire signed [31:0] fine_inc;
  reg ready=1,test_pass=0;
  reg [31:0] iq[0:65535],cfg[0:4];reg bits[0:33047];
  integer n,j,count=0,heads=0,frames=0,cycles=0;reg stalled=0;reg [18:0] held;
  cofdm_phy_rx_v2_top dut(.clk,.rst,.sample_valid(sv),.sample_re(x),.sample_im(y),
    .inv_noise_q16(24'hffffff),.payload_ready(ready),.payload_valid(pv),.payload_last(pl),
    .payload_cw_first(cf),.payload_cw_last(cl),.payload_llr(llr),.header_valid(hv),
    .header_ok(hok),.crc_ok(crc),.payload_bytes(len),.scrambler_seed(seed),.midamble_code(mid),
    .header_error(herr),.header_busy(hbusy),.frame_valid(valid),.capture_locked(locked),
    .capture_timeout(to),.false_alarm_count(false_count),.replay_busy(rb),.replay_done(rd),
    .replay_error(re),.fft_overflow(overflow),.frame_done(done),.frame_error(err),
    .state_dbg(state),.fine_valid(fine_v),.fine_phase_inc(fine_inc));
  always @(negedge clk) begin
    cycles=cycles+1;ready=(cycles%19<13);
  end
  always @(posedge clk) if(!rst) begin
    if(dut.sync_front.stf_candidate) $display("STF index=%d",dut.sync_front.stf_index);
    if(dut.sync_front.ltf_search_error) $display("LTF search error");
    if(dut.sync_front.ltf_peak_valid) $display("LTF peak raw index=%d score=%d",dut.sync_front.ltf_peak_index,dut.sync_front.ltf_peak_score);
    if(dut.peak_valid) $display("LTF index=%d score=%d",dut.peak_index,dut.sync_front.ltf_peak_score);
    if(fine_v) $display("fine CFO increment=%d",fine_inc);
    if(to) $fatal(1,"capture timeout state=%d",dut.sync_front.capture_state);
    if(err || re || overflow) $fatal(1,"RX error state=%d ring=%b fft=%b",state,re,overflow);
    if(hv) begin
      heads=heads+1;
      $display("Header ok=%b crc=%b bytes=%d seed=%d mid=%d",hok,crc,len,seed,mid);
      if(!hok || !crc || len!=cfg[2] || seed!=cfg[3] || mid!=cfg[4]) $fatal(1,"header mismatch");
    end
    if(stalled && (!pv || {cf,cl,pl,llr}!==held)) $fatal(1,"stalled LLR changed");
    stalled=pv && !ready;held={cf,cl,pl,llr};
    if(pv && ready) begin
      if(heads!=1 || count>=cfg[1]) $fatal(1,"unexpected LLR %d",count);
      if(llr==0 || llr[15]!==bits[count]) $fatal(1,"LLR mismatch %d llr=%d bit=%b",count,llr,bits[count]);
      if(cf!==(count%648==0) || cl!==(count%648==647)) $fatal(1,"CW boundary %d",count);
      count=count+1;
    end
    if(valid) frames=frames+1;
    if(done) begin
      if(count!=cfg[1] || frames!=1) $fatal(1,"completion count=%d frames=%d",count,frames);
      test_pass=1;
      $display("PASS actual IQ -> synchronization -> real XFFT -> v2 Header -> %d payload LLR signs",count);
      $finish;
    end
  end
  initial begin
    $readmemh("rx_config.mem",cfg);
    $readmemh("rx_iq.mem",iq,0,cfg[0]-1);
    $readmemh("rx_bits.mem",bits,0,cfg[1]-1);
    repeat(16) @(negedge clk);rst=0;
    for(n=0;n<cfg[0];n=n+1) begin
      sv=1;{y,x}=iq[n];@(negedge clk);sv=0;
      repeat(7) @(negedge clk);
    end
    repeat(100000) @(negedge clk);
    $fatal(1,"timeout state=%d llrs=%d",state,count);
  end
endmodule
