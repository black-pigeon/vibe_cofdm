`timescale 1ns/1ps
// Streaming CFO rotator.
//
// phase_inc is signed turns/sample in Q0.32.  For a received CFO estimate
// f_cfo, use phase_inc = round(-f_cfo/fs * 2^32).  The phase accumulator is
// advanced once per accepted sample.  A 65-entry quarter-wave ROM (256 phase bins) is
// used instead of a CORDIC so the first FPGA prototype has deterministic,
// one-sample throughput and modest control complexity.
module cofdm_cfo_nco_rotator #(
    parameter integer IW = 16,
    parameter integer LUT_W = 16,
    parameter integer PHASE_W = 32
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    clear_phase,
    input  wire                    sample_valid,
    input  wire signed [PHASE_W-1:0] phase_inc,
    input  wire signed [IW-1:0]     in_re,
    input  wire signed [IW-1:0]     in_im,
    output reg                     out_valid,
    output reg signed [IW-1:0]      out_re,
    output reg signed [IW-1:0]      out_im,
    output reg [PHASE_W-1:0]       phase_dbg
);
    initial begin
        if (LUT_W!=16 || PHASE_W<8) $error("NCO requires Q1.15 coefficients and PHASE_W>=8");
    end
    localparam integer PROD_W = IW + LUT_W;
    reg [PHASE_W-1:0] phase;
    reg signed [IW-1:0] in_re_d, in_im_d;
    reg signed [LUT_W-1:0] sin_d, cos_d;
    reg                    sample_d_valid, prod_valid;
    reg [PHASE_W-1:0] phase_d, phase_prod;
    wire [PHASE_W-1:0] used_phase = clear_phase ? '0 : phase;
    wire [7:0] phase_byte = used_phase[PHASE_W-1 -: 8];
    wire [7:0] phase_cos_byte = phase_byte + 8'd64;
    wire signed [LUT_W-1:0] sin_q = sine_lut(phase_byte);
    wire signed [LUT_W-1:0] cos_q = sine_lut(phase_cos_byte);
    reg signed [PROD_W-1:0] re_cos_d, im_sin_d, re_sin_d, im_cos_d;
    wire signed [PROD_W:0] rot_re_wide = re_cos_d - im_sin_d;
    wire signed [PROD_W:0] rot_im_wide = re_sin_d + im_cos_d;
    wire signed [PROD_W:0] rot_re_scaled = rot_re_wide >>> (LUT_W-1);
    wire signed [PROD_W:0] rot_im_scaled = rot_im_wide >>> (LUT_W-1);

    // 65 endpoint-inclusive quarter-wave values: round(32767*sin(k*pi/128)).
    function automatic signed [LUT_W-1:0] base_lut(input [6:0] index);
        begin
            case(index)
                7'd0: base_lut=LUT_W'(0);
                7'd1: base_lut=LUT_W'(804);
                7'd2: base_lut=LUT_W'(1608);
                7'd3: base_lut=LUT_W'(2410);
                7'd4: base_lut=LUT_W'(3212);
                7'd5: base_lut=LUT_W'(4011);
                7'd6: base_lut=LUT_W'(4808);
                7'd7: base_lut=LUT_W'(5602);
                7'd8: base_lut=LUT_W'(6393);
                7'd9: base_lut=LUT_W'(7179);
                7'd10: base_lut=LUT_W'(7962);
                7'd11: base_lut=LUT_W'(8739);
                7'd12: base_lut=LUT_W'(9512);
                7'd13: base_lut=LUT_W'(10278);
                7'd14: base_lut=LUT_W'(11039);
                7'd15: base_lut=LUT_W'(11793);
                7'd16: base_lut=LUT_W'(12539);
                7'd17: base_lut=LUT_W'(13279);
                7'd18: base_lut=LUT_W'(14010);
                7'd19: base_lut=LUT_W'(14732);
                7'd20: base_lut=LUT_W'(15446);
                7'd21: base_lut=LUT_W'(16151);
                7'd22: base_lut=LUT_W'(16846);
                7'd23: base_lut=LUT_W'(17530);
                7'd24: base_lut=LUT_W'(18204);
                7'd25: base_lut=LUT_W'(18868);
                7'd26: base_lut=LUT_W'(19519);
                7'd27: base_lut=LUT_W'(20159);
                7'd28: base_lut=LUT_W'(20787);
                7'd29: base_lut=LUT_W'(21403);
                7'd30: base_lut=LUT_W'(22005);
                7'd31: base_lut=LUT_W'(22594);
                7'd32: base_lut=LUT_W'(23170);
                7'd33: base_lut=LUT_W'(23731);
                7'd34: base_lut=LUT_W'(24279);
                7'd35: base_lut=LUT_W'(24811);
                7'd36: base_lut=LUT_W'(25329);
                7'd37: base_lut=LUT_W'(25832);
                7'd38: base_lut=LUT_W'(26319);
                7'd39: base_lut=LUT_W'(26790);
                7'd40: base_lut=LUT_W'(27245);
                7'd41: base_lut=LUT_W'(27683);
                7'd42: base_lut=LUT_W'(28105);
                7'd43: base_lut=LUT_W'(28510);
                7'd44: base_lut=LUT_W'(28898);
                7'd45: base_lut=LUT_W'(29268);
                7'd46: base_lut=LUT_W'(29621);
                7'd47: base_lut=LUT_W'(29956);
                7'd48: base_lut=LUT_W'(30273);
                7'd49: base_lut=LUT_W'(30571);
                7'd50: base_lut=LUT_W'(30852);
                7'd51: base_lut=LUT_W'(31113);
                7'd52: base_lut=LUT_W'(31356);
                7'd53: base_lut=LUT_W'(31580);
                7'd54: base_lut=LUT_W'(31785);
                7'd55: base_lut=LUT_W'(31971);
                7'd56: base_lut=LUT_W'(32137);
                7'd57: base_lut=LUT_W'(32285);
                7'd58: base_lut=LUT_W'(32412);
                7'd59: base_lut=LUT_W'(32521);
                7'd60: base_lut=LUT_W'(32609);
                7'd61: base_lut=LUT_W'(32678);
                7'd62: base_lut=LUT_W'(32728);
                7'd63: base_lut=LUT_W'(32757);
                7'd64: base_lut=LUT_W'(32767);
                default: base_lut='0;
            endcase
        end
    endfunction
    function automatic signed [LUT_W-1:0] sine_lut(input [7:0] ph);
        reg [6:0] idx;
        reg signed [LUT_W-1:0] v;
        begin
            idx=ph[6] ? (7'd64-{1'b0,ph[5:0]}) : {1'b0,ph[5:0]};
            v=base_lut(idx);
            sine_lut=ph[7] ? -v : v;
        end
    endfunction

    function automatic signed [IW-1:0] sat_iw(input signed [PROD_W:0] v);
        reg signed [PROD_W:0] max_v, min_v;
        begin
            max_v = (1 <<< (IW-1))-1;
            min_v = -(1 <<< (IW-1));
            if (v > max_v) sat_iw = {1'b0,{(IW-1){1'b1}}};
            else if (v < min_v) sat_iw = {1'b1,{(IW-1){1'b0}}};
            else sat_iw = v[IW-1:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            phase <= '0; phase_dbg <= '0; phase_d<='0; phase_prod<='0; out_valid <= 1'b0;
            out_re <= '0; out_im <= '0;
            in_re_d <= '0; in_im_d <= '0; sin_d <= '0; cos_d <= '0;
            sample_d_valid <= 1'b0; prod_valid <= 1'b0;
            re_cos_d <= '0; im_sin_d <= '0; re_sin_d <= '0; im_cos_d <= '0;
        end else begin
            out_valid <= 1'b0;
            if (clear_phase) phase <= '0;
            // Third stage: add/subtract, scale and saturate the registered
            // products.  The multiplier stage is therefore not on the output
            // register's critical path.
            if (prod_valid) begin
                out_valid <= 1'b1;
                phase_dbg<=phase_prod;
                out_re <= sat_iw(rot_re_scaled);
                out_im <= sat_iw(rot_im_scaled);
            end
            // Second stage: four signed products.  Vivado maps these to
            // DSP48E1s and the registers isolate them from the adders.
            prod_valid <= sample_d_valid;
            if (sample_d_valid) begin
                phase_prod<=phase_d;
                re_cos_d <= in_re_d * cos_d;
                im_sin_d <= in_im_d * sin_d;
                re_sin_d <= in_re_d * sin_d;
                im_cos_d <= in_im_d * cos_d;
            end
            // First stage: latch input and the current NCO lookup values.
            sample_d_valid <= sample_valid;
            if (sample_valid) begin
                in_re_d <= in_re; in_im_d <= in_im;
                sin_d <= sin_q; cos_d <= cos_q;
                phase_d <= used_phase;
                phase <= used_phase + phase_inc;
            end
        end
    end
endmodule
