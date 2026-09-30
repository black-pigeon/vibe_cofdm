`timescale 1ns/1ps
// CP removal and AXI4-Stream wrapper for the generated XFFT 9.1 core.
// Input symbol timing: symbol_start marks the first CP sample. The first
// CP_LEN accepted samples are discarded, then NFFT samples are sent to XFFT.
// Input and output use {imag,real}, both signed INPUT_W-bit components.
module cofdm_fft_stream_frontend #(
    parameter integer INPUT_W=16,
    parameter integer NFFT=256,
    parameter integer CP_LEN=32,
    parameter integer CFG_W=16
) (
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire                         in_symbol_start,
    input  wire signed [INPUT_W-1:0]    in_re,
    input  wire signed [INPUT_W-1:0]    in_im,
    output wire                         out_valid,
    input  wire                         out_ready,
    output wire signed [INPUT_W-1:0]    out_re,
    output wire signed [INPUT_W-1:0]    out_im,
    output wire                         out_last,
    output wire [7:0]                   out_user,
    output wire                         frame_started,
    output wire                         fft_overflow,
    output wire                         input_halt,
    output wire                         output_halt,
    output wire                         config_done,
    output wire [31:0]                  accepted_fft_samples
    ,output wire                         out_symbol_start
    ,output wire [7:0]                   out_symbol_index
    ,output wire [2:0]                   out_symbol_kind
    ,output wire [7:0]                   out_bin_index
);
    localparam integer CW = (CP_LEN < 2) ? 1 : $clog2(CP_LEN+1);
    localparam integer NW = (NFFT < 2) ? 1 : $clog2(NFFT);
    // XFFT config: bit 0 = forward transform. Bits [8:1] are the four
    // 2-bit stage scale fields. 0xAB is the XFFT "default" schedule
    // (11,10,10,10), so the complete 16-bit word is 0x0157.
    localparam [CFG_W-1:0] FFT_CONFIG = 16'h0157;

    localparam [1:0] S_IDLE=2'd0, S_CP=2'd1, S_DATA=2'd2;
    reg [1:0] state;
    reg [CW-1:0] cp_count;
    reg [NW-1:0] data_count;
    reg cfg_valid;
    reg [31:0] accepted_count;
    reg [7:0] out_frame_index;
    reg [7:0] out_bin_index_reg;

    wire cfg_ready;
    wire data_ready;
    wire fft_in_valid = in_valid && (state == S_DATA) && cfg_valid==1'b0;
    wire fft_in_last = fft_in_valid && (data_count == NW'(NFFT-1));
    wire source_accept = in_valid && in_ready;
    wire fft_accept = fft_in_valid && data_ready;

    // IDLE also accepts samples so a continuous ADC stream can carry a
    // one-cycle symbol_start marker without waiting for a private ready
    // handshake. Samples accepted in IDLE without the marker are discarded.
    assign in_ready = (state == S_IDLE) || (state == S_CP) ||
                      ((state == S_DATA) && !cfg_valid && data_ready);
    assign config_done = !cfg_valid;
    assign accepted_fft_samples = accepted_count;
    // XFFT preserves frame order.  Count only accepted output bins so output
    // bubbles do not alter metadata.  The first two replayed frames are LTFs;
    // frame 2 is the v2 Header and later frames are payload/midamble frames.
    assign out_symbol_start = out_valid && (out_bin_index_reg == 0);
    assign out_symbol_index = out_frame_index;
    assign out_symbol_kind = (out_frame_index < 2) ? out_frame_index[2:0] :
                             ((out_frame_index == 2) ? 3'd2 : 3'd3);
    assign out_bin_index = out_bin_index_reg;

    cofdm_fft_256 u_fft (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_config_tdata(FFT_CONFIG),
      .s_axis_config_tvalid(cfg_valid),
      .s_axis_config_tready(cfg_ready),
      .s_axis_data_tdata({in_im,in_re}),
      .s_axis_data_tvalid(fft_in_valid),
      .s_axis_data_tready(data_ready),
      .s_axis_data_tlast(fft_in_last),
      .m_axis_data_tdata({out_im,out_re}),
      .m_axis_data_tuser(out_user),
      .m_axis_data_tvalid(out_valid),
      .m_axis_data_tready(out_ready),
      .m_axis_data_tlast(out_last),
      .m_axis_status_tdata(),
      .m_axis_status_tvalid(),
      .m_axis_status_tready(1'b1),
      .event_frame_started(frame_started),
      .event_tlast_unexpected(),
      .event_tlast_missing(),
      .event_fft_overflow(fft_overflow),
      .event_status_channel_halt(),
      .event_data_in_channel_halt(input_halt),
      .event_data_out_channel_halt(output_halt));

    always @(posedge aclk) begin
        if (!aresetn) begin
            state <= S_IDLE;
            cp_count <= '0;
            data_count <= '0;
            cfg_valid <= 1'b1;
            accepted_count <= 32'd0;
            out_frame_index <= 8'd0;
            out_bin_index_reg <= 8'd0;
        end else begin
            if (cfg_valid && cfg_ready) cfg_valid <= 1'b0;
            if (fft_accept) begin
                accepted_count <= accepted_count + 1'b1;
                if (data_count == NW'(NFFT-1)) begin
                    data_count <= '0;
                    state <= S_IDLE;
                end else begin
                    data_count <= data_count + 1'b1;
                end
            end
            if (out_valid && out_ready) begin
                if (out_last) begin
                    out_bin_index_reg <= 8'd0;
                    out_frame_index <= out_frame_index + 1'b1;
                end else begin
                    out_bin_index_reg <= out_bin_index_reg + 1'b1;
                end
            end
            if (source_accept) begin
                case (state)
                    S_IDLE: begin
                        // symbol_start sample is the first CP sample.
                        if (in_symbol_start) begin
                            if (CP_LEN == 0) begin
                                state <= S_DATA;
                                cp_count <= '0;
                            end else begin
                                state <= S_CP;
                                cp_count <= {{(CW-1){1'b0}},1'b1};
                            end
                        end
                    end
                    S_CP: begin
                        if (cp_count == CW'(CP_LEN-1)) begin
                            state <= S_DATA;
                            cp_count <= '0;
                            data_count <= '0;
                        end else begin
                            cp_count <= cp_count + 1'b1;
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
