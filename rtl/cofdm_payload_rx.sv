`timescale 1ns/1ps
// Validated v2 Header + already deinterleaved QPSK LLR -> verified bytes.
// One bounded frame slot (33048 x 7 bits, <=2048 payload bytes). This absorbs
// scalar LDPC latency WITHOUT stalling the ADC ring mid-frame. It does not
// provide continuous air-rate service: caller must honor start_ready; a new
// header while busy is rejected, never overwrites the current frame.
// in_last is symbol-end and is intentionally NOT used as codeword-end.
// The current cofdm_matched_llr output is already an integer LLR.  Keep the
// default at zero; a nonzero shift is an explicit system-level quantizer knob
// to be selected by an SNR sweep, not an implicit loss of six LSBs.
module cofdm_payload_rx #(parameter integer INPUT_SHIFT=0)(
    input wire clk,rst,start,abort_frame,
    output wire start_ready,
    input wire [11:0] payload_bytes,
    input wire [6:0] scrambler_seed,
    input wire in_valid,in_cw_first,in_cw_last,
    input wire signed [15:0] in_llr,
    output wire in_ready,
    output wire out_valid, input wire out_ready,
    output wire [7:0] out_data, output wire out_last,
    output reg frame_done,frame_error,start_rejected,
    output wire busy,crc_ok,padding_ok,ldpc_ok,
    output wire [4:0] decoder_iterations,
    output wire [15:0] codeword_index
);
    localparam [1:0] IDLE=0,CONFIG=1,RUN=2;
    reg [1:0] state;
    reg [11:0] len;
    reg [6:0] seed;
    reg [15:0] nwords,cw_work;
    reg [14:0] remaining;
    reg [15:0] expected_llrs,wr_idx,rd_idx;
    reg [9:0] wr_bit,rd_bit;
    reg bridge_reset,post_start;
    wire accept_start=start && start_ready;
    wire reset_backend=rst|accept_start|bridge_reset|abort_frame;
    wire post_done,post_error,br_error,bit_valid,bit_ready,bit_last,decoded_bit,dec_ok;
    wire fifo_ready;
    reg fifo_valid,read_pending;
    reg signed [6:0] fifo_data;
    (* ram_style="block" *) reg signed [6:0] llr_mem[0:33047];
    wire signed [16:0] extended={in_llr[15],in_llr};
    // Symmetric nearest rounding, ties away from zero; default Q8 -> Q2.
    wire [16:0] mag=extended[16]?$unsigned(-extended):$unsigned(extended);
    wire [17:0] rounded=({1'b0,mag}+((INPUT_SHIFT==0)?18'd0:(18'd1<<(INPUT_SHIFT-1))))>>INPUT_SHIFT;
    wire signed [6:0] clipped=(rounded>63)?7'sd63:$signed(rounded[6:0]);
    wire signed [6:0] quantized=extended[16]?-clipped:clipped;
    wire push=in_valid && in_ready;
    wire pop=fifo_valid && fifo_ready;
    wire rd_en=state==RUN && !fifo_valid && !read_pending && rd_idx<wr_idx;
    assign start_ready=state==IDLE && !rst;
    assign busy=state!=IDLE;
    assign in_ready=state==RUN && wr_idx<expected_llrs && !abort_frame && !rst;
    always @(posedge clk) begin
        if(push) llr_mem[wr_idx]<=quantized;
        if(rd_en) fifo_data<=llr_mem[rd_idx];
    end
    /* verilator lint_off PINCONNECTEMPTY */
    cofdm_payload_codeword_bridge #(.INPUT_LLR_W(7),.INPUT_SHIFT(0)) bridge(
        .clk,.rst(reset_backend),.frame_start(1'b0),.n_codewords(nwords),
        .in_valid(fifo_valid),.in_last(1'b0),.in_cw_first(rd_bit==0),.in_cw_last(rd_bit==647),
        .in_ready(fifo_ready),.in_llr(fifo_data),.out_valid(bit_valid),.out_ready(bit_ready),
        .out_last(bit_last),.out_bit(decoded_bit),.codeword_done(),.frame_done(),
        .frame_error(br_error),.busy(),.codeword_index,.decoder_ok(dec_ok),.decoder_iterations);
    cofdm_payload_postprocess post(.clk,.rst(reset_backend),.start(post_start),.abort_frame(1'b0),
        .payload_bytes(len),.scrambler_seed(seed),.n_codewords(nwords),
        .in_valid(bit_valid),.in_bit(decoded_bit),.in_cw_last(bit_last),.in_decode_ok(dec_ok),.in_ready(bit_ready),
        .out_valid,.out_ready,.out_data,.out_last,.frame_done(post_done),.frame_error(post_error),
        .crc_ok,.padding_ok,.ldpc_ok,.busy());
    /* verilator lint_on PINCONNECTEMPTY */
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;len<=0;seed<=1;nwords<=0;cw_work<=0;remaining<=0;
            expected_llrs<=0;wr_idx<=0;rd_idx<=0;wr_bit<=0;rd_bit<=0;
            bridge_reset<=0;post_start<=0;fifo_valid<=0;read_pending<=0;
            frame_done<=0;frame_error<=0;start_rejected<=0;
        end else begin
            frame_done<=0;frame_error<=0;start_rejected<=start && !start_ready;
            bridge_reset<=0;post_start<=0;
            if(accept_start) begin
                wr_idx<=0;rd_idx<=0;wr_bit<=0;rd_bit<=0;fifo_valid<=0;read_pending<=0;nwords<=0;
                if(payload_bytes==0 || payload_bytes>2048 || scrambler_seed==0) begin frame_error<=1;end
                else begin
                    len<=payload_bytes;seed<=scrambler_seed;
                    remaining<={payload_bytes,3'b0}+15'd32;cw_work<=0;expected_llrs<=0;state<=CONFIG;
                end
            end
            if(state==CONFIG) begin
                cw_work<=cw_work+1'b1;expected_llrs<=expected_llrs+16'd648;
                if(remaining>324) remaining<=remaining-15'd324;
                else begin nwords<=cw_work+1'b1;state<=RUN;post_start<=1;end
            end
            if(state==RUN) begin
                if(push) begin
                    wr_idx<=wr_idx+1'b1;
                    if(wr_bit==647) wr_bit<=0;else wr_bit<=wr_bit+1'b1;
                end
                read_pending<=rd_en;
                if(read_pending) fifo_valid<=1;
                if(pop) begin
                    fifo_valid<=0;rd_idx<=rd_idx+1'b1;
                    if(rd_bit==647) rd_bit<=0;else rd_bit<=rd_bit+1'b1;
                end
                if(post_done) begin frame_done<=1;state<=IDLE;nwords<=0;end
                if(post_error || br_error || (push && ((in_cw_first!=(wr_bit==0)) || (in_cw_last!=(wr_bit==647))))) begin
                    frame_error<=1;state<=IDLE;bridge_reset<=1;nwords<=0;fifo_valid<=0;read_pending<=0;
                end
            end
            if(abort_frame && busy) begin
                frame_error<=1;state<=IDLE;nwords<=0;fifo_valid<=0;read_pending<=0;bridge_reset<=1;
            end
        end
    end
endmodule
