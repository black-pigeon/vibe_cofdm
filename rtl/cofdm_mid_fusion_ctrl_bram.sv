// BRAM-backed MID channel-fusion controller for Xilinx 7-series.
//
// This is the implementation used by the Vivado reference project.  The
// capture path writes one packed record per active carrier into an XPM
// simple-dual-port block RAM.  The output path issues one synchronous BRAM
// read followed by one fusion result per cycle.  The extra read request state
// is intentional: a 7-series BRAM has a registered read output.
module cofdm_mid_fusion_ctrl_bram #(
    parameter integer W = 18,
    parameter integer N_ACTIVE = 200,
    parameter integer FUSE_SHIFT = 2,
    parameter integer ACC_W = 48,
    parameter integer ADDR_W = (N_ACTIVE <= 2) ? 1 : $clog2(N_ACTIVE)
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
    localparam integer LAST_INDEX_INT = N_ACTIVE-1;
    localparam integer MEM_W = 4*W;
    localparam [2:0] IDLE=3'd0, CAPTURE=3'd1, FLUSH=3'd2, DECIDE=3'd3,
                     READ_REQ=3'd4, FUSE_PREP=3'd5, OUTPUT=3'd6;

    reg [2:0] state;
    reg [ADDR_W-1:0] index;
    reg signed [ACC_W-1:0] corr_re_acc, corr_im_acc;
    reg [ACC_W-1:0] innovation_acc, variance_acc;
    reg signed [ACC_W-1:0] corr_re_latched, corr_im_latched;
    reg [ACC_W-1:0] innovation_latched, variance_latched;
    // Registered pilot reducer terms.  The multiplier/square stage is
    // separated from the 48-bit accumulator stage so the critical path does
    // not contain DSP + wide carry propagation in one cycle.
    reg                    pilot_term_valid_d;
    reg signed [ACC_W-1:0] corr_re_term_d, corr_im_term_d;
    reg [ACC_W-1:0]        innovation_term_d, variance_term_d;
    reg signed [W-1:0]     old_re_fuse, old_im_fuse;
    reg signed [W+1:0]     diff_re_fuse, diff_im_fuse;
    reg [MEM_W-1:0] mem_dout;
    reg [ADDR_W-1:0] read_index;
    wire [MEM_W-1:0] mem_din = {fresh_im, fresh_re, old_im, old_re};
    wire [MEM_W-1:0] mem_q;

    // One 72-bit x 256 simple-dual-port RAM.  Vivado maps this to block RAM
    // (two RAMB18E1 primitives for the 72-bit data path on 7-series).
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(ADDR_W), .ADDR_WIDTH_B(ADDR_W),
        .BYTE_WRITE_WIDTH_A(MEM_W), .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"), .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(MEM_W*N_ACTIVE), .READ_DATA_WIDTH_B(MEM_W),
        .READ_LATENCY_B(1), .READ_RESET_VALUE_B("0"),
        .RST_MODE_B("SYNC"), .SIM_ASSERT_CHK(0), .USE_MEM_INIT(0),
        .WRITE_DATA_WIDTH_A(MEM_W)) u_channel_mem (
        .sleep(1'b0), .clka(clk), .ena(sample_valid && (state == CAPTURE)),
        .wea(sample_valid && (state == CAPTURE)),
        .addra(index), .dina(mem_din),
        .injectsbiterra(1'b0), .injectdbiterra(1'b0),
        .clkb(clk), .rstb(rst), .enb(state == READ_REQ), .regceb(1'b1),
        .addrb(read_index), .doutb(mem_q),
        .sbiterrb(), .dbiterrb());

    wire signed [W-1:0] old_re_q = mem_q[W-1:0];
    wire signed [W-1:0] old_im_q = mem_q[2*W-1:W];
    wire signed [W-1:0] fresh_re_q = mem_q[3*W-1:2*W];
    wire signed [W-1:0] fresh_im_q = mem_q[4*W-1:3*W];

    localparam signed [W+1:0] MAX_EXT = {3'b000,{(W-1){1'b1}}};
    localparam signed [W+1:0] MIN_EXT = {3'b111,{(W-1){1'b0}}};
    wire [ACC_W-1:0] abs_corr_re = corr_re_latched[ACC_W-1] ? -corr_re_latched : corr_re_latched;
    wire [ACC_W-1:0] abs_corr_im = corr_im_latched[ACC_W-1] ? -corr_im_latched : corr_im_latched;
    wire signed [W+1:0] rotated_re =
        (rot_code == 2'd0) ? {{2{fresh_re_q[W-1]}},fresh_re_q} :
        (rot_code == 2'd1) ? {{2{fresh_im_q[W-1]}},fresh_im_q} :
        (rot_code == 2'd2) ? -$signed({{2{fresh_re_q[W-1]}},fresh_re_q}) :
                             -$signed({{2{fresh_im_q[W-1]}},fresh_im_q});
    wire signed [W+1:0] rotated_im =
        (rot_code == 2'd0) ? {{2{fresh_im_q[W-1]}},fresh_im_q} :
        (rot_code == 2'd1) ? -$signed({{2{fresh_re_q[W-1]}},fresh_re_q}) :
        (rot_code == 2'd2) ? -$signed({{2{fresh_im_q[W-1]}},fresh_im_q}) :
                             {{2{fresh_re_q[W-1]}},fresh_re_q};
    wire signed [W+1:0] diff_re = rotated_re - {{2{old_re_q[W-1]}},old_re_q};
    wire signed [W+1:0] diff_im = rotated_im - {{2{old_im_q[W-1]}},old_im_q};
    wire signed [W+1:0] step_re = fast_update ? diff_re_fuse : (diff_re_fuse >>> FUSE_SHIFT);
    wire signed [W+1:0] step_im = fast_update ? diff_im_fuse : (diff_im_fuse >>> FUSE_SHIFT);
    wire signed [W+1:0] sum_re = {{2{old_re_fuse[W-1]}},old_re_fuse} + step_re;
    wire signed [W+1:0] sum_im = {{2{old_im_fuse[W-1]}},old_im_fuse} + step_im;

    function automatic signed [W-1:0] sat_w(input signed [W+1:0] value);
        begin
            if (value > MAX_EXT) sat_w = {1'b0,{(W-1){1'b1}}};
            else if (value < MIN_EXT) sat_w = {1'b1,{(W-1){1'b0}}};
            else sat_w = value[W-1:0];
        end
    endfunction

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
            state <= IDLE; index <= '0; read_index <= '0; busy <= 1'b0;
            out_valid <= 1'b0; out_last <= 1'b0; out_re <= '0; out_im <= '0;
            done <= 1'b0; rot_code <= 2'd0; fast_update <= 1'b0;
            corr_re_acc <= '0; corr_im_acc <= '0; innovation_acc <= '0; variance_acc <= '0;
            corr_re_latched <= '0; corr_im_latched <= '0;
            innovation_latched <= '0; variance_latched <= '0;
            pilot_term_valid_d <= 1'b0;
            corr_re_term_d <= '0; corr_im_term_d <= '0;
            innovation_term_d <= '0; variance_term_d <= '0;
            old_re_fuse <= '0; old_im_fuse <= '0;
            diff_re_fuse <= '0; diff_im_fuse <= '0;
        end else begin
            out_valid <= 1'b0; out_last <= 1'b0; done <= 1'b0;
            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1; state <= CAPTURE; index <= '0;
                        corr_re_acc <= '0; corr_im_acc <= '0;
                        innovation_acc <= '0; variance_acc <= '0;
                        pilot_term_valid_d <= 1'b0;
                    end
                end
                CAPTURE: begin
                    busy <= 1'b1;
                    // Consume the previous cycle's registered reducer term.
                    // This is a separate accumulator-only path.
                    if (pilot_term_valid_d) begin
                        corr_re_acc <= corr_re_acc + corr_re_term_d;
                        corr_im_acc <= corr_im_acc + corr_im_term_d;
                        innovation_acc <= innovation_acc + innovation_term_d;
                        variance_acc <= variance_acc + variance_term_d;
                    end
                    if (sample_valid) begin
                        // Register products/squares and the pilot marker. The
                        // final marker is consumed in FLUSH below.
                        pilot_term_valid_d <= sample_pilot;
                        corr_re_term_d <= corr_re_ext;
                        corr_im_term_d <= corr_im_ext;
                        innovation_term_d <= innovation_ext;
                        variance_term_d <= variance_ext;
                        if (index == LAST_INDEX_INT[ADDR_W-1:0] || sample_last) begin
                            state <= FLUSH; index <= '0;
                        end else index <= index + 1'b1;
                    end
                end
                FLUSH: begin
                    // Include the reducer term belonging to the final input
                    // sample before making the decision.
                    corr_re_latched <= corr_re_acc + (pilot_term_valid_d ? corr_re_term_d : '0);
                    corr_im_latched <= corr_im_acc + (pilot_term_valid_d ? corr_im_term_d : '0);
                    innovation_latched <= innovation_acc + (pilot_term_valid_d ? innovation_term_d : '0);
                    variance_latched <= variance_acc + (pilot_term_valid_d ? variance_term_d : '0);
                    pilot_term_valid_d <= 1'b0;
                    state <= DECIDE;
                end
                DECIDE: begin
                    if (abs_corr_re >= abs_corr_im)
                        rot_code <= corr_re_latched[ACC_W-1] ? 2'd2 : 2'd0;
                    else rot_code <= corr_im_latched[ACC_W-1] ? 2'd3 : 2'd1;
                    fast_update <= innovation_latched > (variance_latched << 2);
                    state <= READ_REQ; read_index <= '0; index <= '0;
                end
                READ_REQ: begin
                    // XPM presents mem_q on the cycle after this request.
                    state <= FUSE_PREP;
                end
                FUSE_PREP: begin
                    // Split BRAM output, quadrant rotation and subtraction
                    // from the final shift/add/saturation stage.  This is a
                    // second timing pipeline boundary on the output path.
                    old_re_fuse <= old_re_q;
                    old_im_fuse <= old_im_q;
                    diff_re_fuse <= diff_re;
                    diff_im_fuse <= diff_im;
                    state <= OUTPUT;
                end
                OUTPUT: begin
                    busy <= 1'b1; out_valid <= 1'b1;
                    out_last <= (index == LAST_INDEX_INT[ADDR_W-1:0]);
                    out_re <= sat_w(sum_re); out_im <= sat_w(sum_im);
                    if (index == LAST_INDEX_INT[ADDR_W-1:0]) begin
                        state <= IDLE; busy <= 1'b0; done <= 1'b1;
                    end else begin
                        index <= index + 1'b1;
                        read_index <= index + 1'b1;
                        state <= READ_REQ;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
