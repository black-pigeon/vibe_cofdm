`timescale 1ns/1ps
// Dual-LTF frequency-domain cross accumulator.
//
// The upstream XFFT stream supplies two natural-order 256-point frames.
// symbol_id=0 stores LTF1; symbol_id=1 evaluates
//   Y2 * conj(Y1) * T1 * conj(T2)
// on valid active carriers. rot_re/rot_im are the precomputed Q1.(COEF_W-1)
// values of T1*conj(T2), so no divider or per-bin ZC generator is required.
// The output phase is atan2(sum_im,sum_re), then
// fine_cfo = phase * Fs / (2*pi*(NFFT+CP)).
module cofdm_ltf_fine_cfo_accum #(
    parameter integer IW=16,
    parameter integer COEF_W=16,
    parameter integer ACC_W=64,
    parameter integer NFFT=256,
    parameter integer BIN_W=8,
    parameter integer USE_ROT_ROM=0
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         fft_valid,
    input  wire                         fft_symbol_start,
    input  wire                         fft_last,
    input  wire                         fft_symbol_id,
    input  wire [BIN_W-1:0]             fft_bin_index,
    input  wire                         fft_bin_active,
    input  wire signed [IW-1:0]         fft_re,
    input  wire signed [IW-1:0]         fft_im,
    /* verilator lint_off UNUSED */
    input  wire signed [COEF_W-1:0]     rot_re,
    input  wire signed [COEF_W-1:0]     rot_im,
    /* verilator lint_on UNUSED */
    output reg                          ltf1_stored,
    output reg                          fine_sum_valid,
    output reg signed [ACC_W-1:0]       fine_sum_re,
    output reg signed [ACC_W-1:0]       fine_sum_im,
    output reg [31:0]                   active_count
);
    localparam integer PROD_W = 2*IW;
    localparam integer CROSS_W = PROD_W+1;
    localparam integer ROT_W = CROSS_W+COEF_W;

    (* ram_style="block" *) reg signed [IW-1:0] ltf1_re_mem [0:NFFT-1];
    (* ram_style="block" *) reg signed [IW-1:0] ltf1_im_mem [0:NFFT-1];
    wire signed [IW-1:0] y1_re = ltf1_re_mem[fft_bin_index];
    wire signed [IW-1:0] y1_im = ltf1_im_mem[fft_bin_index];
    wire signed [COEF_W-1:0] rot_rom_re, rot_rom_im;
    generate if (USE_ROT_ROM != 0) begin : gen_rot_rom
      cofdm_ltf_rot_rom u_rot_rom(.addr(fft_bin_index[7:0]),.re(rot_rom_re),.im(rot_rom_im));
    end else begin : gen_no_rot_rom
      assign rot_rom_re = rot_re;
      assign rot_rom_im = rot_im;
    end endgenerate
    wire signed [COEF_W-1:0] rot_re_sel = rot_rom_re;
    wire signed [COEF_W-1:0] rot_im_sel = rot_rom_im;

    // Four complex products are registered first, then the cross-product
    // add/subtract, then the four coefficient products.  This costs three
    // cycles of latency but places DSP48 input/output registers on every
    // multiplier boundary; the previous all-combinational version missed
    // timing by 8.7 ns at 122.88 MHz on XC7Z020.
    reg signed [PROD_W-1:0] p_rr_reg, p_ii_reg, p_ir_reg, p_ri_reg;
    reg signed [CROSS_W-1:0] cross_re_reg, cross_im_reg;
    reg signed [ROT_W-1:0] q_re_reg, q_im_reg;
    reg signed [COEF_W-1:0] rot_re0, rot_im0, rot_re1, rot_im1;
    reg term_valid0, term_valid1, term_valid2;
    reg term_last0, term_last1, term_last2;
    reg term_start0, term_start1, term_start2;
    wire second_start = fft_valid && fft_symbol_start && fft_symbol_id;
    wire second_term = fft_valid && fft_symbol_id && fft_bin_active;
    wire signed [CROSS_W-1:0] cross_re_pipe = $signed({p_rr_reg[PROD_W-1],p_rr_reg}) +
                                               $signed({p_ii_reg[PROD_W-1],p_ii_reg});
    wire signed [CROSS_W-1:0] cross_im_pipe = $signed({p_ir_reg[PROD_W-1],p_ir_reg}) -
                                               $signed({p_ri_reg[PROD_W-1],p_ri_reg});
    wire signed [ROT_W-1:0] q_re_pipe = cross_re_reg * rot_re1 - cross_im_reg * rot_im1;
    wire signed [ROT_W-1:0] q_im_pipe = cross_re_reg * rot_im1 + cross_im_reg * rot_re1;
    wire signed [ROT_W-1:0] q_re_scaled = q_re_reg >>> (COEF_W-1);
    wire signed [ROT_W-1:0] q_im_scaled = q_im_reg >>> (COEF_W-1);
    wire signed [ACC_W-1:0] q_re_acc = {{(ACC_W-ROT_W){q_re_scaled[ROT_W-1]}},q_re_scaled};
    wire signed [ACC_W-1:0] q_im_acc = {{(ACC_W-ROT_W){q_im_scaled[ROT_W-1]}},q_im_scaled};
    wire signed [ACC_W-1:0] base_re = term_start2 ? '0 : fine_sum_re;
    wire signed [ACC_W-1:0] base_im = term_start2 ? '0 : fine_sum_im;
    wire signed [ACC_W-1:0] next_re = base_re + q_re_acc;
    wire signed [ACC_W-1:0] next_im = base_im + q_im_acc;

    always @(posedge clk) begin
        if (rst) begin
            ltf1_stored <= 1'b0;
            fine_sum_valid <= 1'b0;
            fine_sum_re <= '0;
            fine_sum_im <= '0;
            active_count <= 32'd0;
            p_rr_reg <= '0; p_ii_reg <= '0; p_ir_reg <= '0; p_ri_reg <= '0;
            cross_re_reg <= '0; cross_im_reg <= '0;
            q_re_reg <= '0; q_im_reg <= '0;
            rot_re0 <= '0; rot_im0 <= '0; rot_re1 <= '0; rot_im1 <= '0;
            term_valid0 <= 1'b0; term_valid1 <= 1'b0; term_valid2 <= 1'b0;
            term_last0 <= 1'b0; term_last1 <= 1'b0; term_last2 <= 1'b0;
            term_start0 <= 1'b0; term_start1 <= 1'b0; term_start2 <= 1'b0;
        end else begin
            fine_sum_valid <= 1'b0;
            if (fft_valid && !fft_symbol_id) begin
                ltf1_re_mem[fft_bin_index] <= fft_re;
                ltf1_im_mem[fft_bin_index] <= fft_im;
                if (fft_last) ltf1_stored <= 1'b1;
            end
            // Stage 0: capture the four products and frame metadata.
            term_valid0 <= second_term;
            term_last0 <= second_term && fft_last;
            term_start0 <= second_term && second_start;
            if (second_term) begin
                p_rr_reg <= fft_re * y1_re;
                p_ii_reg <= fft_im * y1_im;
                p_ir_reg <= fft_im * y1_re;
                p_ri_reg <= fft_re * y1_im;
                rot_re0 <= rot_re_sel;
                rot_im0 <= rot_im_sel;
            end
            // Stage 1: cross multiplication Y2*conj(Y1).
            term_valid1 <= term_valid0;
            term_last1 <= term_last0;
            term_start1 <= term_start0;
            if (term_valid0) begin
                cross_re_reg <= cross_re_pipe;
                cross_im_reg <= cross_im_pipe;
                rot_re1 <= rot_re0;
                rot_im1 <= rot_im0;
            end
            // Stage 2: rotate by T1*conj(T2).
            term_valid2 <= term_valid1;
            term_last2 <= term_last1;
            term_start2 <= term_start1;
            if (term_valid1) begin
                q_re_reg <= q_re_pipe;
                q_im_reg <= q_im_pipe;
            end
            // Stage 3: restore coefficient scale and accumulate.
            if (term_valid2) begin
                fine_sum_re <= next_re;
                fine_sum_im <= next_im;
                active_count <= active_count + 1'b1;
                if (term_last2) begin
                    fine_sum_valid <= 1'b1;
                    fine_sum_re <= next_re;
                    fine_sum_im <= next_im;
                end
            end
        end
    end
endmodule
