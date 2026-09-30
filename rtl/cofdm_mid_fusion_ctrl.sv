// Streaming MID channel-fusion controller.
//
// Protocol:
//   1. Pulse start. The controller enters CAPTURE.
//   2. Present exactly N_ACTIVE old/fresh channel samples with sample_valid.
//      is_pilot marks the eight pilot carriers. sample_last may be asserted
//      on the final sample; the internal index is still bounded by N_ACTIVE.
//   3. After one DECIDE cycle, out_valid emits N_ACTIVE fused samples in
//      carrier order. out_last marks the final output.
//
// The controller deliberately uses a single stream and one sample/cycle.
// Memory inference can map old/fresh arrays to BRAM; no FFT timing path is
// included here.
module cofdm_mid_fusion_ctrl #(
    parameter integer W = 18,
    parameter integer N_ACTIVE = 200,
    parameter integer FUSE_SHIFT = 2,
    parameter integer ACC_W = 48
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,
    input  wire                    sample_valid,
    input  wire                    sample_last,
    input  wire                    sample_pilot,
    input  wire signed [W-1:0]     old_re,
    input  wire signed [W-1:0]     old_im,
    input  wire signed [W-1:0]     fresh_re,
    input  wire signed [W-1:0]     fresh_im,
    input  wire [W-1:0]            old_var,
    input  wire [W-1:0]            fresh_var,
    output reg                     busy,
    output reg                     out_valid,
    output reg                     out_last,
    output reg signed [W-1:0]      out_re,
    output reg signed [W-1:0]      out_im,
    output reg [1:0]               rot_code,
    output reg                     fast_update,
    output reg                     done
);
    localparam integer IW = (N_ACTIVE <= 2) ? 1 : $clog2(N_ACTIVE);
    localparam integer LAST_INDEX_INT = N_ACTIVE-1;
    localparam signed [W+1:0] MAX_EXT = {3'b000,{(W-1){1'b1}}};
    localparam signed [W+1:0] MIN_EXT = {3'b111,{(W-1){1'b0}}};
    localparam [1:0] IDLE=2'd0, CAPTURE=2'd1, DECIDE=2'd2, OUTPUT=2'd3;
    reg [1:0] state;
    reg [IW-1:0] index;
    reg signed [W-1:0] old_re_mem [0:N_ACTIVE-1];
    reg signed [W-1:0] old_im_mem [0:N_ACTIVE-1];
    reg signed [W-1:0] fresh_re_mem [0:N_ACTIVE-1];
    reg signed [W-1:0] fresh_im_mem [0:N_ACTIVE-1];
    reg signed [ACC_W-1:0] corr_re_acc, corr_im_acc;
    reg [ACC_W-1:0] innovation_acc, variance_acc;
    reg signed [ACC_W-1:0] corr_re_latched, corr_im_latched;
    reg [ACC_W-1:0] innovation_latched, variance_latched;

    wire [ACC_W-1:0] abs_corr_re = corr_re_latched[ACC_W-1] ? -corr_re_latched : corr_re_latched;
    wire [ACC_W-1:0] abs_corr_im = corr_im_latched[ACC_W-1] ? -corr_im_latched : corr_im_latched;
    wire signed [W+1:0] rotated_re =
        (rot_code == 2'd0) ? {{2{fresh_re_mem[index][W-1]}},fresh_re_mem[index]} :
        (rot_code == 2'd1) ? {{2{fresh_im_mem[index][W-1]}},fresh_im_mem[index]} :
        (rot_code == 2'd2) ? -$signed({{2{fresh_re_mem[index][W-1]}},fresh_re_mem[index]}) :
                             -$signed({{2{fresh_im_mem[index][W-1]}},fresh_im_mem[index]});
    wire signed [W+1:0] rotated_im =
        (rot_code == 2'd0) ? {{2{fresh_im_mem[index][W-1]}},fresh_im_mem[index]} :
        (rot_code == 2'd1) ? -$signed({{2{fresh_re_mem[index][W-1]}},fresh_re_mem[index]}) :
        (rot_code == 2'd2) ? -$signed({{2{fresh_im_mem[index][W-1]}},fresh_im_mem[index]}) :
                             {{2{fresh_re_mem[index][W-1]}},fresh_re_mem[index]};
    wire signed [W+1:0] diff_re = rotated_re - {{2{old_re_mem[index][W-1]}},old_re_mem[index]};
    wire signed [W+1:0] diff_im = rotated_im - {{2{old_im_mem[index][W-1]}},old_im_mem[index]};
    wire signed [W+1:0] step_re = fast_update ? diff_re : (diff_re >>> FUSE_SHIFT);
    wire signed [W+1:0] step_im = fast_update ? diff_im : (diff_im >>> FUSE_SHIFT);
    wire signed [W+1:0] sum_re = {{2{old_re_mem[index][W-1]}},old_re_mem[index]} + step_re;
    wire signed [W+1:0] sum_im = {{2{old_im_mem[index][W-1]}},old_im_mem[index]} + step_im;

    function automatic signed [W-1:0] sat_w(input signed [W+1:0] value);
        begin
            if (value > MAX_EXT) sat_w = {1'b0,{(W-1){1'b1}}};
            else if (value < MIN_EXT) sat_w = {1'b1,{(W-1){1'b0}}};
            else sat_w = value[W-1:0];
        end
    endfunction

    // The two products are the only new multipliers in the pilot reducer:
    // (fr+jfi)*(or-joi) = (fr*or+fi*oi) + j(fi*or-fr*oi).
    wire signed [2*W-1:0] p_fr_or = fresh_re * old_re;
    wire signed [2*W-1:0] p_fi_oi = fresh_im * old_im;
    wire signed [2*W-1:0] p_fi_or = fresh_im * old_re;
    wire signed [2*W-1:0] p_fr_oi = fresh_re * old_im;
    wire signed [2*W:0] corr_re_term = p_fr_or + p_fi_oi;
    wire signed [2*W:0] corr_im_term = p_fi_or - p_fr_oi;
    wire signed [W:0] delta_re = fresh_re - old_re;
    wire signed [W:0] delta_im = fresh_im - old_im;
    wire [2*W+1:0] innovation_term = delta_re*delta_re + delta_im*delta_im;
    wire [W:0] variance_term = old_var + fresh_var;
    wire signed [ACC_W-1:0] corr_re_ext = {{(ACC_W-(2*W+1)){corr_re_term[2*W]}},corr_re_term};
    wire signed [ACC_W-1:0] corr_im_ext = {{(ACC_W-(2*W+1)){corr_im_term[2*W]}},corr_im_term};
    wire [ACC_W-1:0] innovation_ext = {{(ACC_W-(2*W+2)){1'b0}},innovation_term};
    wire [ACC_W-1:0] variance_ext = {{(ACC_W-(W+1)){1'b0}},variance_term};
    wire signed [ACC_W-1:0] corr_re_add = sample_pilot ? corr_re_ext : '0;
    wire signed [ACC_W-1:0] corr_im_add = sample_pilot ? corr_im_ext : '0;
    wire [ACC_W-1:0] innovation_add = sample_pilot ? innovation_ext : '0;
    wire [ACC_W-1:0] variance_add = sample_pilot ? variance_ext : '0;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; index <= '0; busy <= 1'b0; out_valid <= 1'b0;
            out_last <= 1'b0; out_re <= '0; out_im <= '0; done <= 1'b0;
            rot_code <= 2'd0; fast_update <= 1'b0;
            corr_re_acc <= '0; corr_im_acc <= '0; innovation_acc <= '0; variance_acc <= '0;
            corr_re_latched <= '0; corr_im_latched <= '0;
            innovation_latched <= '0; variance_latched <= '0;
        end else begin
            out_valid <= 1'b0; out_last <= 1'b0; done <= 1'b0;
            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1; state <= CAPTURE; index <= '0;
                        corr_re_acc <= '0; corr_im_acc <= '0;
                        innovation_acc <= '0; variance_acc <= '0;
                    end
                end
                CAPTURE: begin
                    busy <= 1'b1;
                    if (sample_valid) begin
                        old_re_mem[index] <= old_re; old_im_mem[index] <= old_im;
                        fresh_re_mem[index] <= fresh_re; fresh_im_mem[index] <= fresh_im;
                        if (sample_pilot) begin
                            corr_re_acc <= corr_re_acc + corr_re_ext;
                            corr_im_acc <= corr_im_acc + corr_im_ext;
                            innovation_acc <= innovation_acc + innovation_ext;
                            variance_acc <= variance_acc + variance_ext;
                        end
                        if (index == LAST_INDEX_INT[IW-1:0] || sample_last) begin
                            corr_re_latched <= corr_re_acc + corr_re_add;
                            corr_im_latched <= corr_im_acc + corr_im_add;
                            innovation_latched <= innovation_acc + innovation_add;
                            variance_latched <= variance_acc + variance_add;
                            state <= DECIDE; index <= '0;
                        end else index <= index + 1'b1;
                    end
                end
                DECIDE: begin
                    if (abs_corr_re >= abs_corr_im)
                        rot_code <= corr_re_latched[ACC_W-1] ? 2'd2 : 2'd0;
                    else rot_code <= corr_im_latched[ACC_W-1] ? 2'd3 : 2'd1;
                    fast_update <= innovation_latched > (variance_latched << 2);
                    state <= OUTPUT; index <= '0;
                end
                OUTPUT: begin
                    busy <= 1'b1; out_valid <= 1'b1;
                    out_last <= (index == LAST_INDEX_INT[IW-1:0]);
                    out_re <= sat_w(sum_re); out_im <= sat_w(sum_im);
                    if (index == LAST_INDEX_INT[IW-1:0]) begin
                        state <= IDLE; busy <= 1'b0; done <= 1'b1;
                    end else index <= index + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
