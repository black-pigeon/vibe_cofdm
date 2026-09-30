`timescale 1ns/1ps
module tb_pilot_prbs;
    reg clk=0,rst=1,start=0,req=0,advance=0;
    always #5 clk=~clk;
    wire sign,valid,bin_sign; reg [7:0] bin=0;
    reg expected[0:319]; integer k,s,p; integer map[0:7];
    cofdm_pilot_prbs dut(.clk,.rst,.frame_start(start),.pilot_valid(req),.pilot_sign(sign),.pilot_out_valid(valid));
    cofdm_symbol_pilots symbols(.clk,.rst,.frame_start(start),.advance,.fft_bin(bin),.pilot_sign(bin_sign));
    initial begin
        $readmemh("matlab/vectors/pre_ldpc_stream/pilot_bits.mem",expected);
        map[0]=13;map[1]=39;map[2]=65;map[3]=91;map[4]=165;map[5]=191;map[6]=217;map[7]=243;
        repeat(3) @(negedge clk); rst=0;
        for(p=0;p<2;p=p+1) begin
            start=1; @(negedge clk); start=0;
            for(k=0;k<320;k=k+1) begin
                req=1; @(posedge clk); #1;
                if(!valid || sign!==expected[k]) $fatal(1,"PRBS bit %d",k);
                @(negedge clk); req=0; @(negedge clk);
            end
            for(s=0;s<40;s=s+1) begin
                for(k=0;k<8;k=k+1) begin
                    bin=8'(map[k]); #1;
                    if(bin_sign!==expected[s*8+(k+4)%8]) $fatal(1,"pilot bin order %d/%d",s,k);
                end
                @(negedge clk); advance=1; @(negedge clk); advance=0;
            end
        end
        $display("PASS MATLAB pilot PRBS: 2 x 320 bits and natural-bin symbol order"); $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
