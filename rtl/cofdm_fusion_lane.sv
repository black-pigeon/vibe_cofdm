// One-lane, one-carrier channel fusion kernel.
// rot_code: 0:+1, 1:-j, 2:-1, 3:+j.
// fast_update selects alpha=1; otherwise alpha=1/(2**FUSE_SHIFT).
module cofdm_fusion_lane #(
    parameter integer W = 18,
    parameter integer FUSE_SHIFT = 2
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   in_valid,
    input  wire                   in_last,
    input  wire [1:0]             rot_code,
    input  wire                   fast_update,
    input  wire signed [W-1:0]    old_re,
    input  wire signed [W-1:0]    old_im,
    input  wire signed [W-1:0]    fresh_re,
    input  wire signed [W-1:0]    fresh_im,
    output reg                    out_valid,
    output reg                    out_last,
    output reg signed [W-1:0]     next_re,
    output reg signed [W-1:0]     next_im
);
    localparam signed [W+1:0] MAX_EXT = {3'b000,{(W-1){1'b1}}};
    localparam signed [W+1:0] MIN_EXT = {3'b111,{(W-1){1'b0}}};
    reg signed [W:0] r_re, r_im;
    reg signed [W+1:0] d_re, d_im;
    reg signed [W+1:0] step_re, step_im;
    reg signed [W+1:0] sum_re, sum_im;

    function automatic signed [W-1:0] sat_w(input signed [W+1:0] value);
        begin
            if (value > MAX_EXT) sat_w = {1'b0,{(W-1){1'b1}}};
            else if (value < MIN_EXT) sat_w = {1'b1,{(W-1){1'b0}}};
            else sat_w = value[W-1:0];
        end
    endfunction

    always @* begin
        case (rot_code)
            2'd0: begin r_re = {{1{fresh_re[W-1]}},fresh_re};  r_im = {{1{fresh_im[W-1]}},fresh_im};  end
            2'd1: begin r_re = {{1{fresh_im[W-1]}},fresh_im};  r_im = -$signed({{1{fresh_re[W-1]}},fresh_re}); end
            2'd2: begin r_re = -$signed({{1{fresh_re[W-1]}},fresh_re}); r_im = -$signed({{1{fresh_im[W-1]}},fresh_im}); end
            default: begin r_re = -$signed({{1{fresh_im[W-1]}},fresh_im}); r_im = {{1{fresh_re[W-1]}},fresh_re}; end
        endcase
        d_re = {{1{r_re[W]}},r_re} - {{1{old_re[W-1]}},old_re};
        d_im = {{1{r_im[W]}},r_im} - {{1{old_im[W-1]}},old_im};
        if (fast_update) begin
            step_re = d_re;
            step_im = d_im;
        end else begin
            step_re = d_re >>> FUSE_SHIFT;
            step_im = d_im >>> FUSE_SHIFT;
        end
        sum_re = {{2{old_re[W-1]}},old_re} + step_re;
        sum_im = {{2{old_im[W-1]}},old_im} + step_im;
    end

    always @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_last <= 1'b0;
            next_re <= '0;
            next_im <= '0;
        end else begin
            out_valid <= in_valid;
            out_last <= in_valid && in_last;
            if (in_valid) begin
                next_re <= sat_w(sum_re);
                next_im <= sat_w(sum_im);
            end
        end
    end
endmodule
