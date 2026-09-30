`timescale 1ns/1ps
// Initial frequency-domain channel estimate corresponding to MATLAB:
//
//   H1 = Y1 ./ T1, H2 = Y2 ./ T2, H = (H1 + H2) / 2
//
// The two ZC LTF coefficients have unit magnitude.  Division is therefore
// implemented as a complex multiply by conj(T), followed by the Q1.15
// coefficient shift.  Only ACTIVE_MASK bins are processed.  The second LTF
// stream emits one averaged channel value per active bin and stores it for
// later equalization.  This first implementation deliberately has no
// backpressure: it is intended to sit directly after the one-sample/cycle
// XFFT stream or an AXI FIFO.
module cofdm_ltf_channel_estimator #(
    parameter integer IW = 16,
    parameter integer HW = 18,
    // Fractional bits of the stored channel estimate.  The legacy path used
    // Q?.15; production MATLAB compact_fixed uses Q?.14.  Keeping this as a
    // parameter lets the XFFT scaling contract be selected explicitly.
    parameter integer H_FRAC_BITS = 15,
    parameter integer NV_W = 48,
    parameter integer NV_RECIP_W = 24,
    parameter integer NFFT = 256,
    // Natural-bin mask for MATLAB config.active = -100:-1,1:100.
    // For non-256 transforms the caller must provide an explicit mask.
    parameter [NFFT-1:0] ACTIVE_MASK = (NFFT == 256) ?
      {{{100{1'b1}}},{{55{1'b0}}},{{100{1'b1}}},1'b0} : {NFFT{1'b1}}
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         fft_valid,
    input  wire                         fft_symbol_id,
    input  wire                         fft_last,
    input  wire [$clog2(NFFT)-1:0]      fft_bin_index,
    input  wire                         fft_bin_active,
    input  wire signed [IW-1:0]         fft_re,
    input  wire signed [IW-1:0]         fft_im,
    output wire                         fft_ready,
    output reg                          channel_valid,
    output reg                          channel_last,
    output reg [7:0]                    channel_bin,
    output reg signed [HW-1:0]          channel_re,
    output reg signed [HW-1:0]          channel_im,
    output reg                          channel_done,
    output reg                          channel_error,
    // noise_variance is mean(|H1-H2|^2)/2 in Q0.(2*H_FRAC_BITS).  A
    // reciprocal multiply is used at frame end; no run-time divider is
    // inferred.  noise_valid is asserted with channel_done.
    output reg [NV_W-1:0]                noise_variance,
    output reg                          noise_valid,
    output reg [31:0]                    noise_sample_count,
    input  wire                         h_rd_en,
    input  wire [$clog2(NFFT)-1:0]      h_rd_bin,
    output wire signed [HW-1:0]         h_rd_re,
    output wire signed [HW-1:0]         h_rd_im,
    output wire                         h_valid,
    output wire                         channel_ready
);
    localparam integer BIN_W = (NFFT < 2) ? 1 : $clog2(NFFT);
    localparam integer PW = 2*IW;
    localparam integer CW = PW+1;
    // XFFT complex samples use Q1.(IW-1), and the ZC ROM is Q1.15.
    // The product therefore has 2*(IW-1) fractional bits before narrowing.
    localparam integer PROD_SHIFT = (2*(IW-1))-H_FRAC_BITS;
    localparam integer SQW = 2*HW+1;
    localparam integer POW_W = SQW+1;

    /* verilator lint_off WIDTH */
    function automatic integer count_active(input [NFFT-1:0] mask);
      integer n, c;
      begin c=0; for (n=0; n<NFFT; n=n+1) c=c+mask[n]; count_active=c; end
    endfunction
    function automatic integer last_active(input [NFFT-1:0] mask);
      integer n, last;
      begin last=0; for (n=0; n<NFFT; n=n+1) if (mask[n]) last=n; last_active=last; end
    endfunction
    localparam integer ACTIVE_COUNT = count_active(ACTIVE_MASK);
    localparam integer LAST_ACTIVE_BIN = last_active(ACTIVE_MASK);
    // round(2^NV_RECIP_W/(2*ACTIVE_COUNT)); used only once per LTF pair
    localparam [NV_RECIP_W-1:0] VAR_RECIP =
      (ACTIVE_COUNT > 0) ? ((64'd1 << NV_RECIP_W) + ACTIVE_COUNT) /
                          (2*ACTIVE_COUNT) : {NV_RECIP_W{1'b0}};
    /* verilator lint_on WIDTH */

    wire signed [15:0] t1_re, t1_im, t2_re, t2_im;
    cofdm_ltf_freq_rom u_rom (
      .addr(fft_bin_index[7:0]), .t1_re(t1_re), .t1_im(t1_im),
      .t2_re(t2_re), .t2_im(t2_im));

    // Stage 0 registers the stream sample and ROM coefficient.  Stage 1
    // performs the four DSP products.  This is needed because the natural-bin
    // ROM decode plus an unregistered complex product does not meet 122.88 MHz
    // on XC7Z020.
    reg signed [IW-1:0] y_re0, y_im0;
    reg signed [15:0] t_re0, t_im0;
    reg pipe0_valid, pipe0_id, pipe0_active, pipe0_last;
    reg [BIN_W-1:0] pipe0_bin;
    wire signed [PW-1:0] prod_rr = y_re0 * t_re0;
    wire signed [PW-1:0] prod_ii = y_im0 * t_im0;
    wire signed [PW-1:0] prod_ir = y_im0 * t_re0;
    wire signed [PW-1:0] prod_ri = y_re0 * t_im0;
    wire signed [CW-1:0] raw_re = $signed({prod_rr[PW-1],prod_rr}) +
                                   $signed({prod_ii[PW-1],prod_ii});
    wire signed [CW-1:0] raw_im = $signed({prod_ir[PW-1],prod_ir}) -
                                   $signed({prod_ri[PW-1],prod_ri});
    function automatic signed [HW-1:0] sat_channel(input signed [CW-1:0] x);
      reg signed [CW-1:0] y;
      reg signed [CW-1:0] hi, lo;
      begin
        y = x >>> PROD_SHIFT;
        hi = ({{(CW-HW){1'b0}},1'b0,{(HW-1){1'b1}}});
        lo = ({{(CW-HW){1'b1}},1'b1,{(HW-1){1'b0}}});
        if (y > hi) sat_channel = {1'b0,{(HW-1){1'b1}}};
        else if (y < lo) sat_channel = {1'b1,{(HW-1){1'b0}}};
        else sat_channel = y[HW-1:0];
      end
    endfunction
    wire signed [HW-1:0] h2_re_comb = sat_channel(raw_re);
    wire signed [HW-1:0] h2_im_comb = sat_channel(raw_im);
    reg signed [HW-1:0] h2_re_q, h2_im_q;
    reg h2_valid_q, h2_id_q, h2_active_q, h2_last_q;
    reg [BIN_W-1:0] h2_bin_q;

    (* ram_style="block" *) reg signed [HW-1:0] h1_re_mem [0:NFFT-1];
    (* ram_style="block" *) reg signed [HW-1:0] h1_im_mem [0:NFFT-1];
    (* ram_style="block" *) reg signed [HW-1:0] h_re_mem [0:NFFT-1];
    (* ram_style="block" *) reg signed [HW-1:0] h_im_mem [0:NFFT-1];
    reg channel_ready_reg;
    reg signed [HW-1:0] h_rd_re_reg, h_rd_im_reg;
    reg h_rd_valid_reg;
    wire signed [HW-1:0] old_h1_re = h1_re_mem[h2_bin_q];
    wire signed [HW-1:0] old_h1_im = h1_im_mem[h2_bin_q];
    wire signed [HW:0] old_h1_re_ext = {old_h1_re[HW-1],old_h1_re};
    wire signed [HW:0] old_h1_im_ext = {old_h1_im[HW-1],old_h1_im};
    wire signed [HW:0] h2_re_ext = {h2_re_q[HW-1],h2_re_q};
    wire signed [HW:0] h2_im_ext = {h2_im_q[HW-1],h2_im_q};
    /* verilator lint_off UNUSED */
    wire signed [HW:0] avg_re = (old_h1_re_ext + h2_re_ext) >>> 1;
    wire signed [HW:0] avg_im = (old_h1_im_ext + h2_im_ext) >>> 1;
    /* verilator lint_on UNUSED */
    wire signed [HW-1:0] avg_re_w = avg_re[HW-1:0];
    wire signed [HW-1:0] avg_im_w = avg_im[HW-1:0];

    wire signed [HW:0] diff_re = $signed({var_h2_re[HW-1],var_h2_re}) -
                                  $signed({var_h1_re[HW-1],var_h1_re});
    wire signed [HW:0] diff_im = $signed({var_h2_im[HW-1],var_h2_im}) -
                                  $signed({var_h1_im[HW-1],var_h1_im});
    wire signed [2*HW+1:0] diff_re_sq_q = diff_re_q * diff_re_q;
    wire signed [2*HW+1:0] diff_im_sq_q = diff_im_q * diff_im_q;
    reg [NV_W-1:0] noise_acc;
    // Variance is a side calculation and is deliberately decoupled from the
    // one-bin/cycle channel path.  Registering the squared difference first
    // breaks the ROM -> complex multiply -> square -> accumulator path.
    reg                  var_in_valid, var_in_last;
    reg signed [HW-1:0]  var_h1_re, var_h1_im, var_h2_re, var_h2_im;
    reg signed [HW:0]     diff_re_q, diff_im_q;
    reg                  diff_stage_valid, diff_stage_last;
    reg                  var_pipe_valid, var_pipe_last;
    reg [POW_W-1:0]      var_pipe_power;
    reg [NV_W-1:0]       noise_sum_reg;
    reg                  noise_scale_pending, noise_mul_pending;
    reg [NV_W+NV_RECIP_W-1:0] noise_scaled_reg;

    assign fft_ready = 1'b1;
    assign h_rd_re = h_rd_re_reg;
    assign h_rd_im = h_rd_im_reg;
    assign h_valid = h_rd_valid_reg;
    assign channel_ready = channel_ready_reg;

    initial begin
      if (NFFT != 256) $error("cofdm_ltf_channel_estimator expects 256-bin LTF ROM");
      if (HW < IW) $error("HW must cover the XFFT output width");
    end

    always @(posedge clk) begin
      if (rst) begin
        channel_valid <= 1'b0;
        channel_last <= 1'b0;
        channel_bin <= 8'd0;
        channel_re <= '0;
        channel_im <= '0;
        channel_done <= 1'b0;
        channel_error <= 1'b0;
        noise_variance <= '0;
        noise_valid <= 1'b0;
        noise_sample_count <= 32'd0;
        noise_acc <= '0;
        var_in_valid <= 1'b0;
        var_in_last <= 1'b0;
        var_h1_re <= '0; var_h1_im <= '0;
        var_h2_re <= '0; var_h2_im <= '0;
        diff_re_q <= '0; diff_im_q <= '0;
        diff_stage_valid <= 1'b0; diff_stage_last <= 1'b0;
        var_pipe_valid <= 1'b0;
        var_pipe_last <= 1'b0;
        var_pipe_power <= '0;
        noise_sum_reg <= '0;
        noise_scale_pending <= 1'b0;
        noise_mul_pending <= 1'b0;
        noise_scaled_reg <= '0;
        y_re0 <= '0; y_im0 <= '0; t_re0 <= '0; t_im0 <= '0;
        pipe0_valid <= 1'b0; pipe0_id <= 1'b0; pipe0_active <= 1'b0;
        pipe0_last <= 1'b0; pipe0_bin <= '0;
        h2_re_q <= '0; h2_im_q <= '0; h2_valid_q <= 1'b0;
        h2_id_q <= 1'b0; h2_active_q <= 1'b0; h2_last_q <= 1'b0; h2_bin_q <= '0;
        channel_ready_reg <= 1'b0;
        h_rd_re_reg <= '0;
        h_rd_im_reg <= '0;
        h_rd_valid_reg <= 1'b0;
      end else begin
        channel_valid <= 1'b0;
        channel_last <= 1'b0;
        channel_done <= 1'b0;
        noise_valid <= 1'b0;
        pipe0_valid <= 1'b0;
        h2_valid_q <= 1'b0;
        var_in_valid <= 1'b0;
        diff_stage_valid <= 1'b0;
        var_pipe_valid <= 1'b0;

        // Stage 0: capture every FFT bin so TLAST is preserved even when the
        // final bin is a guard carrier.
        if (fft_valid) begin
          y_re0 <= fft_re;
          y_im0 <= fft_im;
          t_re0 <= fft_symbol_id ? t2_re : t1_re;
          t_im0 <= fft_symbol_id ? t2_im : t1_im;
          pipe0_valid <= 1'b1;
          pipe0_id <= fft_symbol_id;
          pipe0_active <= fft_bin_active && ACTIVE_MASK[fft_bin_index];
          pipe0_last <= fft_last;
          pipe0_bin <= fft_bin_index;
        end
        // Stage 1: registered complex LS observation and metadata.
        if (pipe0_valid) begin
          h2_re_q <= h2_re_comb;
          h2_im_q <= h2_im_comb;
          h2_valid_q <= 1'b1;
          h2_id_q <= pipe0_id;
          h2_active_q <= pipe0_active;
          h2_last_q <= pipe0_last;
          h2_bin_q <= pipe0_bin;
        end

        // Finish the registered variance pipeline.  The reciprocal is a
        // compile-time constant, so Vivado maps this to a single DSP and its
        // input/output registers instead of a long combinational path.
        if (noise_scale_pending) begin
          noise_scaled_reg <= noise_sum_reg * VAR_RECIP;
          noise_scale_pending <= 1'b0;
          noise_mul_pending <= 1'b1;
        end
        if (noise_mul_pending) begin
          /* verilator lint_off WIDTH */
          noise_variance <= noise_scaled_reg >> NV_RECIP_W;
          /* verilator lint_on WIDTH */
          noise_valid <= 1'b1;
          noise_mul_pending <= 1'b0;
        end
        h_rd_valid_reg <= 1'b0;
        if (h_rd_en && channel_ready_reg) begin
          h_rd_re_reg <= h_re_mem[h_rd_bin];
          h_rd_im_reg <= h_im_mem[h_rd_bin];
          h_rd_valid_reg <= 1'b1;
        end
        // Start a fresh variance accumulator at the first bin of LTF2.
        if (!channel_ready_reg && fft_valid && fft_symbol_id &&
            (fft_bin_index == {BIN_W{1'b0}})) begin
          noise_acc <= '0;
          noise_sample_count <= 32'd0;
          var_in_valid <= 1'b0;
          diff_stage_valid <= 1'b0;
          var_pipe_valid <= 1'b0;
        end
        if (!channel_ready_reg && h2_valid_q && h2_active_q) begin
          if (!h2_id_q) begin
            h1_re_mem[h2_bin_q] <= h2_re_q[HW-1:0];
            h1_im_mem[h2_bin_q] <= h2_im_q[HW-1:0];
          end else begin
            h_re_mem[h2_bin_q] <= avg_re_w;
            h_im_mem[h2_bin_q] <= avg_im_w;
            channel_valid <= 1'b1;
            channel_last <= h2_last_q || (h2_bin_q == BIN_W'(LAST_ACTIVE_BIN));
            channel_bin <= h2_bin_q;
            channel_re <= avg_re_w;
            channel_im <= avg_im_w;
          end
        end
        // Stage 0 captures the two channel observations. Stage 1 computes
        // the difference power from those registers; the accumulator then
        // consumes the registered power. This keeps the ROM/complex multiply
        // and square operations in separate cycles at the 122.88 MHz target.
        if (!channel_ready_reg && h2_valid_q && h2_id_q && h2_active_q) begin
          var_in_valid <= 1'b1;
          var_in_last <= h2_last_q || (h2_bin_q == BIN_W'(LAST_ACTIVE_BIN));
          var_h1_re <= old_h1_re;
          var_h1_im <= old_h1_im;
          var_h2_re <= h2_re_q;
          var_h2_im <= h2_im_q;
        end
        if (var_in_valid) begin
          diff_re_q <= diff_re;
          diff_im_q <= diff_im;
          diff_stage_valid <= 1'b1;
          diff_stage_last <= var_in_last;
        end
        if (diff_stage_valid) begin
          var_pipe_valid <= 1'b1;
          var_pipe_last <= diff_stage_last;
          var_pipe_power <= $unsigned(diff_re_sq_q) + $unsigned(diff_im_sq_q);
        end
        if (var_pipe_valid) begin
          noise_acc <= noise_acc + {{(NV_W-POW_W){1'b0}},var_pipe_power};
          noise_sample_count <= noise_sample_count + 1'b1;
          if (var_pipe_last) begin
            noise_sum_reg <= noise_acc + {{(NV_W-POW_W){1'b0}},var_pipe_power};
            noise_scale_pending <= 1'b1;
          end
        end
        // Frame completion is independent of ACTIVE_MASK.  This fixes the
        // common case where the final natural FFT bins are guard/DC bins.
        if (!channel_ready_reg && h2_valid_q && h2_last_q && h2_id_q) begin
          channel_done <= 1'b1;
          channel_ready_reg <= 1'b1;
        end
      end
    end
endmodule
