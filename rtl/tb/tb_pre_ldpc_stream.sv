`timescale 1ns/1ps
module tb_pre_ldpc_stream;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,fs=0,hv=0,hl=0,fv=0,fl=0,sh=0,skip=0,ready=0;
    reg [7:0] hb=0,fb=0; reg signed [15:0] yr=0,yi=0;
    wire hr,fr,ov,oh,osl,cf,cl,done,error; wire signed [15:0] llr;
    reg [31:0] fft_samples[0:3583]; reg [1:0] kinds[0:13]; reg bits[0:4727];
    integer frame,sym,k,count=0,cycle=0; reg stalled=0; reg [19:0] held;
    cofdm_pre_ldpc_stream dut(.clk,.rst,.frame_start(fs),
        .h_load_valid(hv),.h_load_last(hl),.h_load_bin(hb),.h_load_re(18'sd16384),.h_load_im(18'sd0),.h_load_ready(hr),
        .fft_valid(fv),.fft_last(fl),.fft_bin(fb),.fft_re(yr),.fft_im(yi),.fft_ready(fr),
        .symbol_header(sh),.pilot_skip_midamble(skip),.inv_noise_q16(24'd65536),.n_codewords(16'd7),
        .out_valid(ov),.out_ready(ready),.out_llr(llr),.out_header(oh),.out_symbol_last(osl),.out_cw_first(cf),.out_cw_last(cl),
        .symbol_done(done),.frame_error(error));
    always @(negedge clk) begin cycle=cycle+1; ready=(cycle%10000>=7000) && (cycle%17<12); end
    always @(posedge clk) if(!rst && !fs) begin
        if(error) $fatal(1,"stream error");
        if(stalled && (!ov || {cl,cf,osl,oh,llr}!==held)) $fatal(1,"stalled stream changed");
        held={cl,cf,osl,oh,llr}; stalled=ov && !ready;
        if(ov && ready) begin
            if(count>=4728 || llr==0 || llr[15]!==bits[count]) $fatal(1,"LLR bit mismatch %d llr=%d expected=%b",count,llr,bits[count]);
            if(oh!==(count<192) || cf!==((count>=192)&&((count-192)%648==0)) || cl!==((count>=192)&&((count-192)%648==647))) $fatal(1,"framing %d",count);
            if(osl!==((count==191)||(count>=192 && ((count-192)%384==383 || count==4727)))) $fatal(1,"symbol last %d",count);
            count=count+1;
        end
    end
    initial begin
        $readmemh("matlab/vectors/pre_ldpc_stream/stream_fft.mem",fft_samples);
        $readmemh("matlab/vectors/pre_ldpc_stream/stream_kind.mem",kinds);
        $readmemh("matlab/vectors/pre_ldpc_stream/stream_bits.mem",bits);
        repeat(3) @(negedge clk); rst=0;
        for(frame=0;frame<2;frame=frame+1) begin
            fs=1; @(negedge clk); fs=0; count=0; stalled=0;
            for(k=0;k<256;k=k+1) begin hv=1; hb=8'(k); hl=k==255; @(negedge clk); end
            hv=0; hl=0;
            for(sym=0;sym<14;sym=sym+1) begin
                if(kinds[sym]==2) begin
                    skip=1; @(negedge clk); skip=0;
                end else begin
                    sh=kinds[sym]==1;
                    for(k=0;k<256;k=k+1) begin
                        fv=1; fb=8'(k); fl=k==255; {yi,yr}=fft_samples[sym*256+k];
                        @(posedge clk); while(!fr) @(posedge clk);
                        @(negedge clk); fv=0; fl=0;
                        if(k%5==0) @(negedge clk);
                    end
                    wait(done); @(negedge clk);
                end
            end
            wait(count==4728); @(negedge clk);
            if(count!=4728) $fatal(1,"missing output %d",count);
        end
        $display("PASS MATLAB integrated pre-LDPC: 2 frames, 9456 LLR signs, PRBS/MID, stalls and padding"); $finish;
    end
    initial begin #2000000; $fatal(1,"stream timeout"); end
endmodule
