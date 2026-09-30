`timescale 1ns/1ps
module tb_payload_rx;
    reg clk=0;always #4 clk=~clk;
    reg rst=1,start=0,abort_frame=0,iv=0,cf=0,cl=0,ready=0;
    reg [11:0] len;reg [6:0] seed;reg signed [15:0] llr;
    wire sr,ir,ov,ol,done,err,rejected,busy,crc,pad,ldpc;wire [7:0] data;
    wire [4:0] iterations;wire [15:0] cw;
    reg [6:0] llrs[0:33047];reg [7:0] bytes[0:2047];reg [31:0] meta[0:3];
    integer t,i,count=0,cycles=0,events=0,errors=0,done_count=0;
    reg stalled=0;reg [8:0] held;reg expect_ok;
    cofdm_payload_rx #(.INPUT_SHIFT(0)) dut(.clk,.rst,.start,.abort_frame,.start_ready(sr),
        .payload_bytes(len),.scrambler_seed(seed),.in_valid(iv),.in_cw_first(cf),.in_cw_last(cl),.in_llr(llr),
        .in_ready(ir),.out_valid(ov),.out_ready(ready),.out_data(data),.out_last(ol),
        .frame_done(done),.frame_error(err),.start_rejected(rejected),.busy,
        .crc_ok(crc),.padding_ok(pad),.ldpc_ok(ldpc),.decoder_iterations(iterations),.codeword_index(cw));
    always @(negedge clk) begin cycles=cycles+1;ready=(cycles%19<11);end
    always @(posedge clk) if(!rst) begin
        if(stalled && (!ov || {ol,data}!==held)) $fatal(1,"payload unstable when stalled");
        stalled=ov&&!ready;held={ol,data};
        if(ov&&ready) begin
            if(!expect_ok || count>=len || data!==bytes[count] || ol!==(count==len-1))
                $fatal(1,"case %0d byte %0d got=%h exp=%h last=%b",t,count,data,bytes[count],ol);
            count=count+1;
        end
        if(done) begin
            if(!expect_ok || count!=len || !crc || !pad || !ldpc) $fatal(1,"bad frame_done");
            events=events+1;done_count=done_count+1;
        end
        if(err) begin
            if(expect_ok || count!=0) $fatal(1,"unexpected frame_error case=%0d count=%0d",t,count);
            events=events+1;errors=errors+1;
        end
    end
    initial begin
        repeat(4) @(negedge clk);rst=0;@(negedge clk);
        for(t=0;t<7;t=t+1) begin
            $readmemh($sformatf("matlab/vectors/qcldpc/frame%0d_meta.mem",t),meta);
            $readmemh($sformatf("matlab/vectors/qcldpc/frame%0d_llr.mem",t),llrs,0,meta[2]*648-1);
            $readmemh($sformatf("matlab/vectors/qcldpc/frame%0d_bytes.mem",t),bytes,0,meta[0]-1);
            count=0;expect_ok=meta[3]!=0;len=meta[0][11:0];seed=meta[1][6:0];
            if(!sr) $fatal(1,"not ready for frame");
            start=1;@(negedge clk);start=0;
            while(!ir) @(negedge clk);
            // Input bursts at 1 LLR/clock; >8192 LLR maximum-length frame.
            for(i=0;i<meta[2]*648;i=i+1) begin
                if(!ir) $fatal(1,"bounded frame RAM unexpectedly full");
                iv=1;cf=(i%648==0);cl=(i%648==647);llr={{9{llrs[i][6]}},llrs[i]};
                @(negedge clk);
            end
            iv=0;cf=0;cl=0;
            wait(events==t+1);@(negedge clk);repeat(5) @(negedge clk);
            if(ov) $fatal(1,"late data");
            $display("PASS Payload MATLAB frame %0d bytes=%0d accepted=%0d cw=%0d",t,len,expect_ok,meta[2]);
        end
        // Truncated frame: explicit abort, then malformed codeword markers.
        expect_ok=0;len=37;seed=93;start=1;@(negedge clk);start=0;
        wait(ir);@(negedge clk);abort_frame=1;@(negedge clk);abort_frame=0;
        wait(events==8);@(negedge clk);repeat(3) @(negedge clk);
        start=1;@(negedge clk);start=0;wait(ir);@(negedge clk);
        iv=1;cf=0;cl=0;llr=24;@(negedge clk);iv=0;
        wait(events==9);@(negedge clk);
        if(done_count!=5 || errors!=4) $fatal(1,"event counts");
        $display("PASS Payload: 5 variable lengths, CRC/padding rejection, abort, bad markers, stalls");$finish;
    end
    initial begin #100000000;$fatal(1,"Payload timeout state=%d decoder=%d",dut.state,dut.bridge.decoder.state);end
endmodule
