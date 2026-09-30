`timescale 1ns/1ps
// Resource-aware LTF time-domain matcher.
//
// search_start marks the first sample of a short candidate window.  The
// default 17 lanes evaluate 17 adjacent 256-sample windows in parallel,
// using one complex MAC per lane and sample.  This is intentionally a local
// search around the STF-derived nominal position; a wider search is obtained
// by increasing CANDIDATES or by running another window.  The design stores
// no full sample window and therefore has deterministic streaming latency.
//
// At the end, the largest correlation is selected first.  score_q16 is a
// calibrated power-of-two projection of the correlation magnitude.  It has
// no divider on the sample-rate path; AGC should keep the input close to the
// Q1.15 training level.  A reciprocal LUT can be added later if fully
// gain-invariant scoring is required.
module cofdm_ltf_time_matcher #(
    parameter integer IW = 16,
    parameter integer NFFT = 256,
    parameter integer CANDIDATES = 17,
    parameter integer ACC_W = 48,
    parameter integer INDEX_W = 32,
    parameter integer RAW_SCORE_SHIFT = 51
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         sample_valid,
    input  wire signed [IW-1:0]         sample_re,
    input  wire signed [IW-1:0]         sample_im,
    input  wire                         search_start,
    input  wire [INDEX_W-1:0]           search_base_index,
    output wire                         search_ready,
    output reg                          search_busy,
    output reg                          peak_valid,
    output reg [15:0]                   peak_score,
    output reg [INDEX_W-1:0]            peak_index,
    output reg signed [ACC_W-1:0]       peak_corr_re,
    output reg signed [ACC_W-1:0]       peak_corr_im,
    output reg [47:0]                   peak_energy,
    output reg                          search_error
);
    localparam integer CW = (CANDIDATES < 2) ? 1 : $clog2(CANDIDATES);
    localparam integer SW = (NFFT+CANDIDATES < 2) ? 1 : $clog2(NFFT+CANDIDATES);
    localparam integer PROD_W = 2*IW;
    localparam integer ENERGY_W = 2*IW+1;
    localparam [SW-1:0] LAST_SAMPLE = SW'(NFFT+CANDIDATES-2);

    reg [SW-1:0] sample_count;
    reg [INDEX_W-1:0] base_index_reg;
    reg pending;
    reg signed [ACC_W-1:0] corr_re [0:CANDIDATES-1];
    reg signed [ACC_W-1:0] corr_im [0:CANDIDATES-1];
    reg [47:0] sample_energy [0:CANDIDATES-1];

    wire signed [PROD_W-1:0] sample_rr = sample_re * sample_re;
    wire signed [PROD_W-1:0] sample_ii = sample_im * sample_im;
    wire [ENERGY_W-1:0] sample_pow = $unsigned(sample_rr) + $unsigned(sample_ii);
    assign search_ready = !search_busy && !pending;

    wire signed [15:0] tmpl_re [0:CANDIDATES-1];
    wire signed [15:0] tmpl_im [0:CANDIDATES-1];
    genvar g;
    generate for (g=0; g<CANDIDATES; g=g+1) begin : gen_templates
        wire [7:0] addr = 8'((sample_count) - SW'(g));
        cofdm_ltf_template_rom u_rom(.addr(addr),.re(tmpl_re[g]),.im(tmpl_im[g]));
    end endgenerate

    wire signed [PROD_W-1:0] prod_rr [0:CANDIDATES-1];
    wire signed [PROD_W-1:0] prod_ii [0:CANDIDATES-1];
    wire signed [PROD_W-1:0] prod_ir [0:CANDIDATES-1];
    wire signed [PROD_W-1:0] prod_ri [0:CANDIDATES-1];
    generate for (g=0; g<CANDIDATES; g=g+1) begin : gen_products
        assign prod_rr[g] = sample_re * tmpl_re[g];
        assign prod_ii[g] = sample_im * tmpl_im[g];
        assign prod_ir[g] = sample_im * tmpl_re[g];
        assign prod_ri[g] = sample_re * tmpl_im[g];
    end endgenerate

    integer i;
    reg [2*ACC_W:0] best_mag;
    reg [CW-1:0] best_lane;
    reg signed [ACC_W-1:0] best_re, best_im;
    reg [47:0] best_energy;
    reg [2*ACC_W:0] lane_mag;
    reg [15:0] raw_score;
    always @* begin
        best_mag = '0; best_lane = '0; best_re = '0; best_im = '0; best_energy = '0;
        for (i=0; i<CANDIDATES; i=i+1) begin
            lane_mag = corr_re[i] * corr_re[i] + corr_im[i] * corr_im[i];
            if (lane_mag >= best_mag) begin
                best_mag = lane_mag;
                best_lane = CW'(i);
                best_re = corr_re[i];
                best_im = corr_im[i];
                best_energy = sample_energy[i];
            end
        end
        if (best_mag >> RAW_SCORE_SHIFT > 65535)
            raw_score = 16'hffff;
        else
            raw_score = 16'(best_mag >> RAW_SCORE_SHIFT);
    end

    always @(posedge clk) begin
        if (rst) begin
            search_busy <= 1'b0; pending <= 1'b0; sample_count <= '0;
            base_index_reg <= '0; peak_valid <= 1'b0; peak_score <= '0;
            peak_index <= '0; peak_corr_re <= '0; peak_corr_im <= '0;
            peak_energy <= '0; search_error <= 1'b0;
            for (i=0; i<CANDIDATES; i=i+1) begin
                corr_re[i] <= '0; corr_im[i] <= '0; sample_energy[i] <= '0;
            end
        end else begin
            peak_valid <= 1'b0;
            if (pending) begin
                // The last input sample was accumulated on the prior clock.
                peak_valid <= 1'b1;
                peak_score <= raw_score;
                peak_index <= base_index_reg + INDEX_W'(best_lane);
                peak_corr_re <= best_re;
                peak_corr_im <= best_im;
                peak_energy <= best_energy;
                pending <= 1'b0;
            end
            if (search_start && search_ready) begin
                search_busy <= 1'b1;
                sample_count <= '0;
                base_index_reg <= search_base_index;
                search_error <= 1'b0;
                for (i=0; i<CANDIDATES; i=i+1) begin
                    corr_re[i] <= '0; corr_im[i] <= '0; sample_energy[i] <= '0;
                end
                // A marker may coincide with the first sample.  Include it
                // in lane zero so a controller can run continuously without
                // inserting an otherwise artificial idle cycle.
                if (sample_valid) begin
                    corr_re[0] <= $signed({{(ACC_W-PROD_W){prod_rr[0][PROD_W-1]}},prod_rr[0]}) +
                                  $signed({{(ACC_W-PROD_W){prod_ii[0][PROD_W-1]}},prod_ii[0]});
                    corr_im[0] <= $signed({{(ACC_W-PROD_W){prod_ir[0][PROD_W-1]}},prod_ir[0]}) -
                                  $signed({{(ACC_W-PROD_W){prod_ri[0][PROD_W-1]}},prod_ri[0]});
                    sample_energy[0] <= {{(48-ENERGY_W){1'b0}},sample_pow};
                    sample_count <= {{(SW-1){1'b0}},1'b1};
                end
            end else if (search_busy && sample_valid) begin
                for (i=0; i<CANDIDATES; i=i+1) begin
                    if ((sample_count >= SW'(i)) && (sample_count < SW'(i+NFFT))) begin
                        // conj(template) * sample
                        corr_re[i] <= corr_re[i] + $signed({{(ACC_W-PROD_W){prod_rr[i][PROD_W-1]}},prod_rr[i]}) +
                                                    $signed({{(ACC_W-PROD_W){prod_ii[i][PROD_W-1]}},prod_ii[i]});
                        corr_im[i] <= corr_im[i] + $signed({{(ACC_W-PROD_W){prod_ir[i][PROD_W-1]}},prod_ir[i]}) -
                                                    $signed({{(ACC_W-PROD_W){prod_ri[i][PROD_W-1]}},prod_ri[i]});
                        sample_energy[i] <= sample_energy[i] + {{(48-ENERGY_W){1'b0}},sample_pow};
                    end
                end
                if (sample_count == LAST_SAMPLE) begin
                    search_busy <= 1'b0;
                    pending <= 1'b1;
                end else begin
                    sample_count <= sample_count + 1'b1;
                end
            end else if (search_busy && !sample_valid) begin
                // Input bubbles are legal; the sample counter only advances
                // on accepted samples, exactly like the XFFT adapter.
            end
        end
    end
endmodule
