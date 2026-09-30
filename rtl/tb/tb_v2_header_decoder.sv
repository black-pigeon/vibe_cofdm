`timescale 1ns/1ps
module tb_v2_header_decoder;
  reg clk=0,rst=1,start=0,v=0,last=0; always #5 clk=~clk;
  reg signed [15:0] x; wire ready,hv,hok,crc,err,busy;
  wire [11:0] len; wire [6:0] seed; wire [1:0] mid;
  reg [15:0] vec[0:191]; integer k,n,case_errors;
  cofdm_v2_header_decoder dut(.clk,.rst,.start,.in_valid(v),.in_last(last),.in_ready(ready),.in_llr(x),
    .header_valid(hv),.header_ok(hok),.payload_bytes(len),.scrambler_seed(seed),.midamble_code(mid),.crc_ok(crc),.header_error(err),.busy);
  task run_case(input string file,input integer expected_ok,input integer expected_len,input integer expected_seed,input integer expected_mid);
    begin
      $readmemh(file,vec); repeat(2) @(negedge clk); start=1; @(negedge clk); start=0;
      for(k=0;k<192;k=k+1) begin
        while(!ready) @(negedge clk);
        v=1; last=(k==191); x=vec[k]; @(negedge clk); v=0; last=0;
      end
      wait(hv); #1;
      if(hok!==expected_ok || (expected_ok && crc!==expected_ok) || (expected_ok &&
          (len!==expected_len || seed!==expected_seed || mid!==expected_mid))) begin
        $display("FAIL %s ok=%b crc=%b len=%d seed=%d mid=%d",file,hok,crc,len,seed,mid); case_errors=case_errors+1;
      end else $display("PASS %s ok=%b len=%d seed=%d mid=%d",file,hok,len,seed,mid);
      @(negedge clk);
    end
  endtask
  initial begin
    case_errors=0; repeat(3) @(negedge clk); rst=0;
    run_case("matlab/vectors/v2_header/valid_1.mem",1,1,1,0);
    run_case("matlab/vectors/v2_header/valid_2.mem",1,257,93,1);
    run_case("matlab/vectors/v2_header/valid_3.mem",1,2048,127,2);
    run_case("matlab/vectors/v2_header/invalid_fields.mem",0,1,1,0);
    if(case_errors) $fatal(1,"v2 header errors=%0d",case_errors);
    $display("PASS v2 Header Viterbi/CRC/field validation"); $finish;
  end
  initial begin #1000000; $fatal(1,"timeout"); end
endmodule
