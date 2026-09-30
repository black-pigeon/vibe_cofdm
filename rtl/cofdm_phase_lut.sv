`timescale 1ns/1ps
// Quarter-wave sine ROM for the common phase rotator.  The phase input uses
// one signed 32-bit turn (top 8 bits address 0..255); 0x40 is +pi/2.
// A quarter-wave ROM keeps the implementation in LUT/BRAM instead of using
// a second CORDIC for every data carrier.
module cofdm_phase_lut(input wire [7:0] addr,
                       output reg signed [15:0] cos_q15,
                       output reg signed [15:0] sin_q15);
  function automatic [15:0] qsin(input [6:0] a);
    begin case(a)
      7'd0: qsin=16'd0;
      7'd1: qsin=16'd804;
      7'd2: qsin=16'd1608;
      7'd3: qsin=16'd2410;
      7'd4: qsin=16'd3212;
      7'd5: qsin=16'd4011;
      7'd6: qsin=16'd4808;
      7'd7: qsin=16'd5602;
      7'd8: qsin=16'd6393;
      7'd9: qsin=16'd7179;
      7'd10: qsin=16'd7962;
      7'd11: qsin=16'd8739;
      7'd12: qsin=16'd9512;
      7'd13: qsin=16'd10278;
      7'd14: qsin=16'd11039;
      7'd15: qsin=16'd11793;
      7'd16: qsin=16'd12539;
      7'd17: qsin=16'd13279;
      7'd18: qsin=16'd14010;
      7'd19: qsin=16'd14732;
      7'd20: qsin=16'd15446;
      7'd21: qsin=16'd16151;
      7'd22: qsin=16'd16846;
      7'd23: qsin=16'd17530;
      7'd24: qsin=16'd18204;
      7'd25: qsin=16'd18868;
      7'd26: qsin=16'd19519;
      7'd27: qsin=16'd20159;
      7'd28: qsin=16'd20787;
      7'd29: qsin=16'd21403;
      7'd30: qsin=16'd22005;
      7'd31: qsin=16'd22594;
      7'd32: qsin=16'd23170;
      7'd33: qsin=16'd23731;
      7'd34: qsin=16'd24279;
      7'd35: qsin=16'd24811;
      7'd36: qsin=16'd25329;
      7'd37: qsin=16'd25832;
      7'd38: qsin=16'd26319;
      7'd39: qsin=16'd26790;
      7'd40: qsin=16'd27245;
      7'd41: qsin=16'd27683;
      7'd42: qsin=16'd28105;
      7'd43: qsin=16'd28510;
      7'd44: qsin=16'd28898;
      7'd45: qsin=16'd29268;
      7'd46: qsin=16'd29621;
      7'd47: qsin=16'd29956;
      7'd48: qsin=16'd30273;
      7'd49: qsin=16'd30571;
      7'd50: qsin=16'd30852;
      7'd51: qsin=16'd31113;
      7'd52: qsin=16'd31356;
      7'd53: qsin=16'd31580;
      7'd54: qsin=16'd31785;
      7'd55: qsin=16'd31971;
      7'd56: qsin=16'd32137;
      7'd57: qsin=16'd32285;
      7'd58: qsin=16'd32412;
      7'd59: qsin=16'd32521;
      7'd60: qsin=16'd32609;
      7'd61: qsin=16'd32678;
      7'd62: qsin=16'd32728;
      7'd63: qsin=16'd32757;
      7'd64: qsin=16'd32767;
      default: qsin=16'd32767;
    endcase end
  endfunction
  reg signed [15:0] smag;
  always @* begin
    // Fold the full-turn address into the first quadrant.  The small ROM is
    // sampled at 256/4=64 points; 32 is pi/2 in the quarter-wave table.
    case (addr[7:6])
      2'd0: begin smag=$signed(qsin({1'b0,addr[5:0]})); sin_q15=smag; cos_q15=$signed(qsin(7'd64-{1'b0,addr[5:0]})); end
      2'd1: begin smag=$signed(qsin(7'd64-{1'b0,addr[5:0]})); sin_q15=smag; cos_q15=-$signed(qsin({1'b0,addr[5:0]})); end
      2'd2: begin smag=-$signed(qsin({1'b0,addr[5:0]})); sin_q15=smag; cos_q15=-$signed(qsin(7'd64-{1'b0,addr[5:0]})); end
      default: begin smag=-$signed(qsin(7'd64-{1'b0,addr[5:0]})); sin_q15=smag; cos_q15=$signed(qsin({1'b0,addr[5:0]})); end
    endcase
  end
endmodule
