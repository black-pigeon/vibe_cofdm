`timescale 1ns/1ps
module tb_qcldpc_648_vector;
  reg clk=0;always #4 clk=~clk;
  reg rst=1,start=0,iv=0,il=0,ready=0;reg signed [6:0] x;
  reg [6:0] v[0:647];reg expected[0:323];reg [8:0] post[0:647];reg [7:0] meta[0:1];
  wire ir,ov,ol,bit_o,done,ok,synd,busy,err;wire [4:0] it;
  integer i,n=0,t,cycle=0,begin_cycle;reg stalled=0;reg [1:0] held;
  integer checked_rows=0,decisions=0,first_round_passes=0,limit_failures=0;
  reg check_transition=0,expected_exit=0,expected_ok=0;
  cofdm_qcldpc_648_decoder dut(.clk,.rst,.start,.in_valid(iv),.in_ready(ir),.in_last(il),.in_llr(x),
    .out_valid(ov),.out_ready(ready),.out_last(ol),.out_bit(bit_o),.done,
    .decode_ok(ok),.syndrome_ok(synd),.iterations_done(it),.frame_error(err),.busy);
  always @(negedge clk) begin cycle=cycle+1;ready=(cycle%11<7);end
  always @(posedge clk) if(!rst) begin
    if(err) $fatal(1,"vector decoder frame error");
    // Check the actual control path, not only the final decoded bits.
    if(check_transition) begin
      if(expected_exit) begin
        if(dut.state!==dut.OREQ || ok!==expected_ok || synd!==expected_ok)
          $fatal(1,"early-stop/limit decision did not immediately enter output");
      end else if(dut.state!==dut.ROM)
        $fatal(1,"failed parity must continue iteration before the limit");
      check_transition=0;
    end
    if(dut.state==dut.PARITY && dut.marker) checked_rows=checked_rows+1;
    if(dut.state==dut.DECIDE) begin
      if(checked_rows!=324) $fatal(1,"decision before all parity checks: %0d",checked_rows);
      decisions=decisions+1;checked_rows=0;
      if(it!==5'(decisions) || decisions>12) $fatal(1,"iteration count/limit mismatch");
      expected_ok=!dut.bad_checks;
      expected_exit=expected_ok || decisions==12;
      check_transition=1;
      if(expected_ok && decisions==1) first_round_passes=first_round_passes+1;
      if(!expected_ok && decisions==12) limit_failures=limit_failures+1;
    end
    if(stalled && (!ov || {ol,bit_o}!==held)) $fatal(1,"unstable output under stall");
    stalled=ov && !ready;held={ol,bit_o};
    if(ov && ready) begin
      if(n>=324 || bit_o!==expected[n] || ol!==(n==323)) $fatal(1,"case %0d info mismatch bit %0d",t,n);
      n=n+1;
    end
  end
  initial begin
    repeat(4) @(negedge clk);rst=0;
    // No reset between codewords: stale messages must be ignored on iteration 0.
    for(t=0;t<8;t=t+1) begin
      $readmemh($sformatf("matlab/vectors/qcldpc/llr%0d.mem",t),v);
      $readmemh($sformatf("matlab/vectors/qcldpc/bits%0d.mem",t),expected);
      $readmemh($sformatf("matlab/vectors/qcldpc/meta%0d.mem",t),meta);
      $readmemh($sformatf("matlab/vectors/qcldpc/post%0d.mem",t),post);
      n=0;decisions=0;checked_rows=0;begin_cycle=cycle;start=1;@(negedge clk);start=0;
      for(i=0;i<648;i=i+1) begin
        while(!ir) @(negedge clk);
        iv=1;il=(i==647);x=v[i];@(negedge clk);iv=0;il=0;
        if(i%7==0) @(negedge clk);
      end
      wait(done);@(negedge clk);
      if(n!=324 || ok!==meta[0][0] || synd!==meta[0][0] || it!==meta[1][4:0])
        $fatal(1,"case %0d status mismatch ok=%b iter=%0d expected=%0d/%0d",t,ok,it,meta[0],meta[1]);
      for(i=0;i<648;i=i+1) if(dut.post_mem[i]!==post[i])
        $fatal(1,"case %0d post[%0d]=%0d MATLAB=%0d",t,i,dut.post_mem[i],$signed(post[i]));
      $display("PASS MATLAB QC-LDPC case=%0d ok=%b iterations=%0d all 648 posterior values match cycles=%0d",t,ok,it,cycle-begin_cycle);
    end
    if(first_round_passes==0 || limit_failures==0)
      $fatal(1,"missing first-round early-stop or iteration-limit failure coverage");
    $display("PASS SNR-independent early-stop: first-round=%0d limit-failure=%0d; full parity each round, no reset between words",first_round_passes,limit_failures);
    $finish;
  end
  initial begin #30000000;$fatal(1,"timeout");end
endmodule
