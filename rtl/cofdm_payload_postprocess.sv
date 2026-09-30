`timescale 1ns/1ps
// Decoded systematic bits -> descramble -> CRC32/padding/LDPC gate -> bytes.
// CRC is project non-reflected 0x04c11db7, init/final XOR zero, NOT Ethernet.
// Bytes remain in bounded 2048-byte BRAM until ALL checks pass. out_last is
// packet end; frame_done pulses only on acceptance of the final output byte.
module cofdm_payload_postprocess(
    input wire clk,rst,start,abort_frame,
    input wire [11:0] payload_bytes,
    input wire [6:0] scrambler_seed,
    input wire [15:0] n_codewords,
    input wire in_valid,in_bit,in_cw_last,in_decode_ok,
    output wire in_ready,
    output reg out_valid, input wire out_ready,
    output reg [7:0] out_data, output reg out_last,
    output reg frame_done,frame_error,
    output reg crc_ok,padding_ok,ldpc_ok,
    output wire busy
);
    localparam [2:0] IDLE=0,RECEIVE=1,CHECK=2,READ=3,HOLD=4;
    reg [2:0] state;
    reg [11:0] len;
    reg [15:0] cw_total,cw_count;
    reg [8:0] cw_bit;
    reg [14:0] bit_count,data_bits,used_bits;
    reg [6:0] prbs;
    reg [31:0] crc;
    reg pad_bad,decode_bad;
    // Seven previous bits plus the current bit form a complete byte on the
    // eighth input.  Keeping only the rolling seven bits avoids an unused
    // register bit while preserving the full byte at the BRAM write.
    reg [6:0] byte_shift;
    reg [10:0] rd_addr;
    (* ram_style="block" *) reg [7:0] bytes_mem[0:2047];
    reg [7:0] rd_data;
    wire bit_plain=in_bit^prbs[0];
    wire take=in_valid && in_ready;
    wire [31:0] crc_next={crc[30:0],1'b0}^((crc[31]^bit_plain)?32'h04c11db7:32'd0);
    assign busy=state!=IDLE;
    assign in_ready=state==RECEIVE && !rst && !abort_frame;
    always @(posedge clk) begin
        if(take && bit_count<data_bits && bit_count[2:0]==7)
            bytes_mem[bit_count[13:3]]<={byte_shift,bit_plain};
        if(state==READ) rd_data<=bytes_mem[rd_addr];
    end
    always @(posedge clk) begin
        if(rst || abort_frame) begin
            state<=IDLE;len<=0;cw_total<=0;cw_count<=0;cw_bit<=0;bit_count<=0;
            data_bits<=0;used_bits<=0;prbs<=1;crc<=0;pad_bad<=0;decode_bad<=0;
            byte_shift<=0;rd_addr<=0;out_valid<=0;out_data<=0;out_last<=0;
            frame_done<=0;frame_error<=0;crc_ok<=0;padding_ok<=0;ldpc_ok<=0;
        end else begin
            frame_done<=0;frame_error<=0;
            case(state)
            IDLE: if(start) begin
                if(payload_bytes==0 || payload_bytes>2048 || scrambler_seed==0 ||
                   n_codewords==0 || n_codewords>51) frame_error<=1;
                else begin
                    len<=payload_bytes;cw_total<=n_codewords;cw_count<=0;cw_bit<=0;
                    data_bits<={payload_bytes,3'b000};used_bits<={payload_bytes,3'b000}+15'd32;
                    bit_count<=0;prbs<=scrambler_seed;crc<=0;pad_bad<=0;decode_bad<=0;
                    byte_shift<=0;crc_ok<=0;padding_ok<=0;ldpc_ok<=0;state<=RECEIVE;
                end
            end
            RECEIVE: if(take) begin
                if(in_cw_last!=(cw_bit==323)) begin frame_error<=1;state<=IDLE;end
                else begin
                    prbs<={prbs[0]^prbs[3],prbs[6:1]};bit_count<=bit_count+1'b1;
                    decode_bad<=decode_bad|!in_decode_ok;
                    if(bit_count<used_bits) crc<=crc_next;
                    else pad_bad<=pad_bad|bit_plain;
                    if(bit_count<data_bits) byte_shift<={byte_shift[5:0],bit_plain};
                    if(in_cw_last) begin
                        cw_bit<=0;cw_count<=cw_count+1'b1;
                        if(cw_count+1'b1==cw_total) state<=CHECK;
                    end else cw_bit<=cw_bit+1'b1;
                end
            end
            CHECK: begin
                crc_ok<=crc==0;padding_ok<=!pad_bad;ldpc_ok<=!decode_bad;
                // Information padding is always 0..323 bits for minimal Ncw.
                if(crc!=0 || pad_bad || decode_bad || bit_count<used_bits || bit_count-used_bits>=324) begin
                    frame_error<=1;state<=IDLE;
                end else begin rd_addr<=0;state<=READ;end
            end
            READ: state<=HOLD;
            HOLD: begin
                if(!out_valid) begin out_data<=rd_data;out_last<=({1'b0,rd_addr}+12'd1==len);out_valid<=1;end
                else if(out_ready) begin
                    out_valid<=0;out_last<=0;
                    if(out_last) begin frame_done<=1;state<=IDLE;end
                    else begin rd_addr<=rd_addr+1'b1;state<=READ;end
                end
            end
            default:state<=IDLE;
            endcase
        end
    end
endmodule
