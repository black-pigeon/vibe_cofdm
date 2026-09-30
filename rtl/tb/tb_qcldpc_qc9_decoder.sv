`timescale 1ns/1ps
module tb_qcldpc_qc9_decoder;
  reg clk=0; always #4 clk=~clk;
  reg rst=1,start=0,iv=0,il=0,ready=1;
  reg signed [6:0] x;
  reg [6:0] v[0:647]; reg expected[0:323]; reg [8:0] post[0:647]; reg [7:0] meta[0:1];
  wire ir,ov,ol,bit_o,done,ok,synd,busy,err; wire [4:0] it;
  integer i,t,n,cycle=0,begin_cycle;
  cofdm_qcldpc_qc9_decoder dut(.clk,.rst,.start,.in_valid(iv),.in_last(il),.in_ready(ir),.in_llr(x),
    .out_valid(ov),.out_ready(ready),.out_last(ol),.out_bit(bit_o),.done,
    .decode_ok(ok),.syndrome_ok(synd),.iterations_done(it),.frame_error(err),.busy);
  always @(posedge clk) if(!rst) begin
    cycle=cycle+1;
    if(err) $fatal(1,"QC9 frame error");
    if(ov && ready) begin
      if(n>=324 || bit_o!==expected[n] || ol!==(n==323))
        $fatal(1,"case %0d output mismatch bit %0d",t,n);
      n=n+1;
    end
  end
  initial begin
    repeat(4) @(negedge clk); rst=0;
    for(t=0;t<8;t=t+1) begin
      $readmemh($sformatf("matlab/vectors/qcldpc/llr%0d.mem",t),v);
      $readmemh($sformatf("matlab/vectors/qcldpc/bits%0d.mem",t),expected);
      $readmemh($sformatf("matlab/vectors/qcldpc/meta%0d.mem",t),meta);
      $readmemh($sformatf("matlab/vectors/qcldpc/post%0d.mem",t),post);
      n=0; begin_cycle=cycle; start=1; @(negedge clk); start=0;
      for(i=0;i<648;i=i+1) begin
        while(!ir) @(negedge clk);
        iv=1; il=(i==647); x=v[i]; @(negedge clk); iv=0; il=0;
      end
      wait(done); @(negedge clk);
      if(n!=324 || ok!==meta[0][0] || synd!==meta[0][0] || it!==meta[1][4:0])
        $fatal(1,"case %0d status mismatch ok=%b iter=%0d expected=%0d/%0d",t,ok,it,meta[0],meta[1]);
      for(i=0;i<648;i=i+1)
        if(dut.post_mem[i]!==post[i]) $fatal(1,"case %0d post[%0d]=%0d MATLAB=%0d",t,i,dut.post_mem[i],$signed(post[i]));
      $display("PASS QC9 case=%0d ok=%b iterations=%0d cycles=%0d",t,ok,it,cycle-begin_cycle);
    end
    $finish;
  end
  initial begin #30000000; $fatal(1,"QC9 timeout"); end
endmodule
