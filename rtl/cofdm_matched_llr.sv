`timescale 1ns/1ps
// Pipelined matched-filter soft demapper before LDPC.
// S0 registers Y/H/inv_noise, S1 computes the complex matched product, S2
// applies inverse-noise scaling, and S3 saturates the LLR.  The cuts keep the
// BRAM/LUT to DSP path within the XC7Z020 122.88 MHz timing target.
module cofdm_matched_llr #(
    parameter integer YW=16, parameter integer HW=18,
    parameter integer LLR_W=16, parameter integer INV_W=24,
    parameter integer LLR_SHIFT=29+16-8
) (
    input wire clk, input wire rst,
    input wire in_valid, input wire mode_bpsk,
    input wire signed [YW-1:0] y_re, input wire signed [YW-1:0] y_im,
    input wire signed [HW-1:0] h_re, input wire signed [HW-1:0] h_im,
    input wire [INV_W-1:0] inv_noise_q16,
    output wire in_ready,
    output reg out_valid, output reg out_last,
    output reg signed [LLR_W-1:0] llr_re, output reg signed [LLR_W-1:0] llr_im,
    output reg saturated
);
  localparam integer PW=YW+HW, CW=PW+1, MW=CW+INV_W;
  localparam signed [LLR_W-1:0] LMAX={1'b0,{(LLR_W-1){1'b1}}};
  localparam signed [LLR_W-1:0] LMIN={1'b1,{(LLR_W-1){1'b0}}};
  wire signed [MW-1:0] LMAX_EXT={{(MW-LLR_W){LMAX[LLR_W-1]}},LMAX};
  wire signed [MW-1:0] LMIN_EXT={{(MW-LLR_W){LMIN[LLR_W-1]}},LMIN};

  reg signed [YW-1:0] y_re0,y_im0;
  reg signed [HW-1:0] h_re0,h_im0;
  reg [INV_W-1:0] inv0,inv1;
  reg mode0,mode1,mode2;
  reg v0,v1,v2;
  reg signed [CW-1:0] m_re1,m_im1;
  reg signed [MW-1:0] q_re2,q_im2;
  wire signed [PW-1:0] p_rr=y_re0*h_re0;
  wire signed [PW-1:0] p_ii=y_im0*h_im0;
  wire signed [PW-1:0] p_ir=y_im0*h_re0;
  wire signed [PW-1:0] p_ri=y_re0*h_im0;
  wire signed [CW-1:0] m_re0=$signed({p_rr[PW-1],p_rr})+$signed({p_ii[PW-1],p_ii});
  wire signed [CW-1:0] m_im0=$signed({p_ir[PW-1],p_ir})-$signed({p_ri[PW-1],p_ri});
  wire signed [MW-1:0] scaled_re=m_re1*$signed({1'b0,inv1});
  wire signed [MW-1:0] scaled_im=m_im1*$signed({1'b0,inv1});

  function automatic signed [LLR_W-1:0] sat_llr(input signed [MW-1:0] x);
    begin
      if(x>LMAX_EXT) sat_llr=LMAX;
      else if(x<LMIN_EXT) sat_llr=LMIN;
      else sat_llr=x[LLR_W-1:0];
    end
  endfunction
  assign in_ready=1'b1;

  always @(posedge clk) begin
    if(rst) begin
      y_re0<='0; y_im0<='0; h_re0<='0; h_im0<='0; inv0<='0; inv1<='0;
      mode0<=0; mode1<=0; mode2<=0; v0<=0; v1<=0; v2<=0;
      m_re1<='0; m_im1<='0; q_re2<='0; q_im2<='0;
      out_valid<=0; out_last<=0; llr_re<='0; llr_im<='0; saturated<=0;
    end else begin
      v0<=in_valid; v1<=v0; v2<=v1;
      out_valid<=v2; out_last<=v2; saturated<=0;
      if(in_valid) begin
        y_re0<=y_re; y_im0<=y_im; h_re0<=h_re; h_im0<=h_im;
        inv0<=inv_noise_q16; mode0<=mode_bpsk;
      end
      if(v0) begin
        m_re1<=m_re0; m_im1<=m_im0; inv1<=inv0; mode1<=mode0;
      end
      if(v1) begin
        q_re2<=scaled_re >>> LLR_SHIFT;
        q_im2<=scaled_im >>> LLR_SHIFT;
        mode2<=mode1;
      end
      if(v2) begin
        if(mode2) begin
          llr_re<=sat_llr(q_re2); llr_im<='0;
          saturated<=(q_re2>LMAX_EXT)||(q_re2<LMIN_EXT);
        end else begin
          llr_re<=sat_llr(q_re2); llr_im<=sat_llr(q_im2);
          saturated<=(q_re2>LMAX_EXT)||(q_re2<LMIN_EXT)||
                     (q_im2>LMAX_EXT)||(q_im2<LMIN_EXT);
        end
      end
    end
  end
endmodule
