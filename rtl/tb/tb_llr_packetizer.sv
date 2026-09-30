`timescale 1ns/1ps
module tb_llr_packetizer;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,fs=0,ss=0,sh=0,iv=0,il=0,ready=0;
    reg [7:0] bin=0;
    reg signed [15:0] re=0,im=0;
    wire sr,ov,oh,osl,cf,cl,done,err;
    wire signed [15:0] llr;
    reg [7:0] bin_table[0:191]; reg [31:0] pairs[0:1535];
    reg [15:0] expected[0:2063]; reg [3:0] flags[0:2063];
    integer sym,k,count=0,cycle=0,pass;
    reg stalled=0; reg [19:0] held;
    cofdm_llr_packetizer dut(.clk,.rst,.frame_start(fs),.n_codewords(16'd2),
        .symbol_start(ss),.symbol_header(sh),.symbol_ready(sr),
        .in_valid(iv),.in_last(il),.in_bin(bin),.in_re(re),.in_im(im),
        .out_valid(ov),.out_ready(ready),.out_llr(llr),.out_header(oh),
        .out_symbol_last(osl),.out_cw_first(cf),.out_cw_last(cl),.symbol_done(done),.frame_error(err));
    always @(negedge clk) begin cycle=cycle+1; ready=(cycle%7<4 && cycle%101<90); end
    always @(posedge clk) if(!rst && !fs) begin
        if(err) $fatal(1,"packetizer error");
        if(stalled && (!ov || {cl,cf,osl,oh,llr}!==held)) $fatal(1,"output changed under stall");
        stalled=ov && !ready; held={cl,cf,osl,oh,llr};
        if(ov && ready) begin
            if(count>=2064 || llr!==expected[count] || {cl,cf,osl,oh}!==flags[count])
                $fatal(1,"packetizer mismatch %d got=%d flags=%h expected=%d/%h",count,llr,{cl,cf,osl,oh},$signed(expected[count]),flags[count]);
            count=count+1;
        end
    end
    initial begin
        $readmemh("matlab/vectors/pre_ldpc_stream/bins.mem",bin_table);
        $readmemh("matlab/vectors/pre_ldpc_stream/pairs.mem",pairs);
        $readmemh("matlab/vectors/pre_ldpc_stream/expected.mem",expected);
        $readmemh("matlab/vectors/pre_ldpc_stream/flags.mem",flags);
        repeat(3) @(negedge clk); rst=0;
        for(pass=0;pass<2;pass=pass+1) begin
            fs=1; @(negedge clk); fs=0; count=0; stalled=0;
            for(sym=0;sym<8;sym=sym+1) begin
                wait(sr); @(negedge clk); ss=1; sh=(sym<4);
                @(negedge clk); ss=0;
                for(k=0;k<192;k=k+1) begin
                    @(negedge clk); iv=1; il=(k==191); bin=bin_table[k];
                    {im,re}=pairs[sym*192+k];
                    @(negedge clk); iv=0; il=0;
                end
                wait(done); @(negedge clk);
            end
            if(count!=2064) $fatal(1,"missing LLRs %d",count);
        end
        $display("PASS MATLAB packetizer 2 frames: 4128 LLRs, stalls, cw boundaries, padding"); $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
