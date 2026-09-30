// Vivado reference top: BRAM-backed channel fusion followed by a block FIFO.
// The FIFO is the same buffering point that can later connect to an AXI4
// Stream packetizer or the equalizer pipeline.
module cofdm_mid_fusion_ref_top #(
    parameter integer W = 18,
    parameter integer N_ACTIVE = 200
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
    output wire                    busy,
    output wire                    done,
    input  wire                    result_ready,
    output wire                    result_valid,
    output wire                    result_last,
    output wire signed [W-1:0]     result_re,
    output wire signed [W-1:0]     result_im,
    output wire                    fifo_full,
    output wire                    fifo_empty
);
    localparam integer FIFO_W = 2*W + 1;
    localparam integer FIFO_AW = 8;
    wire ctrl_valid, ctrl_last;
    wire signed [W-1:0] ctrl_re, ctrl_im;
    wire [1:0] ctrl_rot;
    wire ctrl_fast;
    wire [FIFO_W-1:0] fifo_din = {ctrl_last, ctrl_im, ctrl_re};
    wire [FIFO_W-1:0] fifo_dout;
    wire fifo_data_valid;

    cofdm_mid_fusion_ctrl_bram #(.W(W), .N_ACTIVE(N_ACTIVE)) u_ctrl (
        .clk, .rst, .start, .sample_valid, .sample_last, .sample_pilot,
        .old_re, .old_im, .fresh_re, .fresh_im, .old_var, .fresh_var,
        .busy, .out_valid(ctrl_valid), .out_last(ctrl_last),
        .out_re(ctrl_re), .out_im(ctrl_im), .rot_code(ctrl_rot),
        .fast_update(ctrl_fast), .done);

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("block"), .FIFO_WRITE_DEPTH(256),
        .WRITE_DATA_WIDTH(FIFO_W), .READ_DATA_WIDTH(FIFO_W),
        .READ_MODE("std"), .FIFO_READ_LATENCY(1),
        .WR_DATA_COUNT_WIDTH(FIFO_AW), .RD_DATA_COUNT_WIDTH(FIFO_AW),
        // 0x1000 enables data_valid; 0x0707 keeps the flag/count features.
        .USE_ADV_FEATURES("1707"), .SIM_ASSERT_CHK(0)
    ) u_result_fifo (
        .sleep(1'b0), .rst(rst), .wr_clk(clk),
        .wr_en(ctrl_valid && !fifo_full), .din(fifo_din), .full(fifo_full),
        .prog_full(), .wr_data_count(), .overflow(), .wr_rst_busy(),
        .almost_full(), .wr_ack(), .rd_en(result_ready && !fifo_empty),
        .dout(fifo_dout), .empty(fifo_empty), .prog_empty(), .rd_data_count(),
        .underflow(), .rd_rst_busy(), .almost_empty(),
        .data_valid(fifo_data_valid), .injectsbiterr(1'b0),
        .injectdbiterr(1'b0), .sbiterr(), .dbiterr());

    assign result_valid = fifo_data_valid;
    assign result_last = fifo_dout[FIFO_W-1];
    assign result_im = fifo_dout[2*W-1:W];
    assign result_re = fifo_dout[W-1:0];
endmodule
