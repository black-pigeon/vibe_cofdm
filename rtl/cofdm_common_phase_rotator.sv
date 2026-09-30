`timescale 1ns/1ps
// One-carrier common-phase correction.  A symbol-level CORDIC estimates the
// pilot phase; this datapath reuses a 256-entry phase LUT for every data bin.
// The two input registers and one output register deliberately isolate the
// four DSP48 products from the LUT decode.
module cofdm_common_phase_rotator #(
    parameter integer IW=16,
    parameter integer CW=16,
    parameter integer OW=16
) (
    input wire clk, input wire rst,
    input wire in_valid,
    /* verilator lint_off UNUSED */
    input wire signed [31:0] phase,
    /* verilator lint_on UNUSED */
    input wire signed [IW-1:0] in_re, input wire signed [IW-1:0] in_im,
    output reg out_valid,
    output reg signed [OW-1:0] out_re, output reg signed [OW-1:0] out_im
);
  /* verilator lint_off UNUSED */
  // Only the top 8 phase bits address the 256-entry LUT; the lower bits are
  // intentionally quantized to keep one shared low-cost rotator.
  /* verilator lint_on UNUSED */
  reg signed [IW-1:0] yr_q, yi_q;
  reg signed [15:0] c_q, s_q;
  reg v_q, v_rr;
  reg signed [32:0] rr_q, ii_q;
  wire signed [31:0] p_rc = yr_q*c_q;
  wire signed [31:0] p_is = yi_q*s_q;
  wire signed [31:0] p_ic = yi_q*c_q;
  wire signed [31:0] p_rs = yr_q*s_q;
  wire signed [32:0] rr = $signed({p_rc[31],p_rc}) + $signed({p_is[31],p_is});
  wire signed [32:0] ii = $signed({p_ic[31],p_ic}) - $signed({p_rs[31],p_rs});
  wire signed [32:0] rr_scaled = rr >>> 15;
  wire signed [32:0] ii_scaled = ii >>> 15;
  function automatic signed [OW-1:0] sat(input signed [32:0] x);
    reg signed [32:0] hi,lo;
    begin
      hi={{(33-OW){1'b0}},1'b0,{(OW-1){1'b1}}};
      lo={{(33-OW){1'b1}},1'b1,{(OW-1){1'b0}}};
      if(x>hi) sat={1'b0,{(OW-1){1'b1}}};
      else if(x<lo) sat={1'b1,{(OW-1){1'b0}}};
      else sat=x[OW-1:0];
    end
  endfunction
  wire signed [15:0] lut_c,lut_s;
  cofdm_phase_lut u_lut(.addr(phase[31:24]),.cos_q15(lut_c),.sin_q15(lut_s));
  always @(posedge clk) begin
    if(rst) begin yr_q<='0; yi_q<='0; c_q<=16'sd32767; s_q<='0; v_q<=1'b0; v_rr<=1'b0; rr_q<='0; ii_q<='0; out_valid<=1'b0; out_re<='0; out_im<='0; end
    else begin
      out_valid<=v_rr;
      if(v_rr) begin out_re<=sat(rr_q); out_im<=sat(ii_q); end
      v_rr<=v_q;
      if(v_q) begin rr_q<=rr_scaled; ii_q<=ii_scaled; end
      v_q<=in_valid;
      if(in_valid) begin yr_q<=in_re; yi_q<=in_im; c_q<=lut_c; s_q<=lut_s; end
    end
  end
endmodule
