`timescale 1ns/1ps
// Low-resource LTF matcher for XC7Z020.
//
// The streaming input is first stored in a short BRAM-friendly sample
// buffer.  The correlation is then evaluated one candidate and one sample
// at a time with one shared complex multiplier (four real products).  This
// trades 3*256*number-of-candidates clocks for DSPs; at a 122.88 MHz PL
// clock a 17-candidate search completes in about 107 us and uses no
// candidate-wide multiplier bank.
module cofdm_ltf_time_matcher_tdm #(
    parameter integer ABSOLUTE_INDEX = 0,
    parameter integer IW = 16,
    parameter integer NFFT = 256,
    parameter integer CANDIDATES = 17,
    parameter integer ACC_W = 48,
    parameter integer INDEX_W = 32,
    parameter integer RAW_SCORE_SHIFT = 18,
    parameter integer TIMEOUT_CYCLES = 18000,
    parameter integer TRACK_ENERGY = 0
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
    localparam integer BUF_LEN = NFFT + CANDIDATES - 1;
    localparam integer PTR_W = (BUF_LEN < 2) ? 1 : $clog2(BUF_LEN);
    localparam integer MEM_DEPTH = (1 << PTR_W);
    localparam integer CW = (CANDIDATES < 2) ? 1 : $clog2(CANDIDATES);
    localparam integer OW = (NFFT < 2) ? 1 : $clog2(NFFT);
    localparam integer PROD_W = 2*IW;
    localparam integer ENERGY_W = 2*IW+1;
    localparam integer ENERGY_ACC_W = 32;
    localparam integer ENERGY_SHIFT = 8;
    // L1 magnitude (|Re|+|Im|) avoids a 48x48 square on the capture path.
    // It preserves the peak ordering needed for timing and costs only an
    // adder/absolute-value tree.  The score shift is calibrated accordingly.
    localparam integer MAG_W = ACC_W+1;
    localparam integer TW = (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES+1);

    typedef enum logic [2:0] {IDLE, CAPTURE, SCAN_REQ, SCAN_ACC, MAC_ADD, EVAL, EVAL2} state_t;
    state_t state;
    reg [PTR_W-1:0] wr_ptr;
    reg [CW-1:0] candidate;
    reg [OW-1:0] offset;
    reg [INDEX_W-1:0] base_index_reg;
    reg [INDEX_W-1:0] sample_index_abs;
    always @(posedge clk) begin
      if(rst) sample_index_abs<=0;
      else if(sample_valid) sample_index_abs<=sample_index_abs+1'b1;
    end
    reg [TW-1:0] timeout_count;

    // Synchronous read port.  SCAN_REQ presents the address and SCAN_ACC
    // consumes the registered result one clock later.
    wire signed [2*IW-1:0] rd_data;
    wire signed [IW-1:0] rd_re = rd_data[2*IW-1:IW];
    wire signed [IW-1:0] rd_im = rd_data[IW-1:0];

    wire [7:0] tmpl_addr = offset[7:0];
    wire signed [15:0] tmpl_re;
    wire signed [15:0] tmpl_im;
`ifdef COFDM_XILINX_ROM
    cofdm_ltf_template_rom_xilinx u_rom(.clk(clk), .addr(tmpl_addr), .re(tmpl_re), .im(tmpl_im));
`else
    cofdm_ltf_template_rom u_rom(.addr(tmpl_addr), .re(tmpl_re), .im(tmpl_im));
`endif

    wire signed [PROD_W-1:0] prod_rr = rd_re * tmpl_re;
    wire signed [PROD_W-1:0] prod_ii = rd_im * tmpl_im;
    wire signed [PROD_W-1:0] prod_ir = rd_im * tmpl_re;
    wire signed [PROD_W-1:0] prod_ri = rd_re * tmpl_im;
    wire signed [PROD_W-1:0] sample_re_sq = $signed(rd_re) * $signed(rd_re);
    wire signed [PROD_W-1:0] sample_im_sq = $signed(rd_im) * $signed(rd_im);
    wire [ENERGY_W-1:0] sample_pow = {{(ENERGY_W-PROD_W){1'b0}},$unsigned(sample_re_sq)} +
                                      {{(ENERGY_W-PROD_W){1'b0}},$unsigned(sample_im_sq)};
    wire [ENERGY_ACC_W-1:0] sample_pow_scaled = ENERGY_ACC_W'(sample_pow >> ENERGY_SHIFT);

    reg signed [ACC_W-1:0] corr_re, corr_im;
    reg [ENERGY_ACC_W-1:0] energy_acc;
    reg signed [ACC_W-1:0] prod_re_reg, prod_im_reg;
    reg [ENERGY_ACC_W-1:0] pow_reg;
    reg [MAG_W-1:0] best_mag;
    reg [CW-1:0] best_candidate;
    reg signed [ACC_W-1:0] best_re, best_im;
    reg [47:0] best_energy;
    reg [MAG_W-1:0] eval_mag;
    reg signed [ACC_W-1:0] eval_re, eval_im;
    reg [47:0] eval_energy;

    wire signed [ACC_W-1:0] prod_re_ext =
        $signed({{(ACC_W-PROD_W){prod_rr[PROD_W-1]}},prod_rr}) +
        $signed({{(ACC_W-PROD_W){prod_ii[PROD_W-1]}},prod_ii});
    wire signed [ACC_W-1:0] prod_im_ext =
        $signed({{(ACC_W-PROD_W){prod_ir[PROD_W-1]}},prod_ir}) -
        $signed({{(ACC_W-PROD_W){prod_ri[PROD_W-1]}},prod_ri});
    wire [ACC_W-1:0] corr_re_abs = corr_re[ACC_W-1] ? $unsigned(-corr_re) : $unsigned(corr_re);
    wire [ACC_W-1:0] corr_im_abs = corr_im[ACC_W-1] ? $unsigned(-corr_im) : $unsigned(corr_im);
    wire [MAG_W-1:0] corr_mag = {1'b0,corr_re_abs} + {1'b0,corr_im_abs};
    wire [15:0] score_from_mag =
        ((eval_mag >> RAW_SCORE_SHIFT) > 65535) ? 16'hffff : 16'(eval_mag >> RAW_SCORE_SHIFT);
    assign search_ready = (state == IDLE);
    wire [PTR_W-1:0] scan_addr = PTR_W'(candidate) + PTR_W'(offset);

    wire mem_wr_en = sample_valid && ((state == IDLE && search_start) || (state == CAPTURE));
    wire [PTR_W-1:0] mem_wr_addr = (state == IDLE) ? '0 : wr_ptr;
    wire mem_rd_en = (state == SCAN_REQ);
    cofdm_ltf_sample_buffer #(.ADDR_W(PTR_W),.DEPTH(MEM_DEPTH)) u_sample_buffer (
        .clk(clk), .rst(rst), .wr_en(mem_wr_en), .wr_addr(mem_wr_addr),
        .wr_data({sample_re,sample_im}), .rd_en(mem_rd_en),
        .rd_addr(scan_addr), .rd_data(rd_data));

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; search_busy <= 1'b0; peak_valid <= 1'b0;
            peak_score <= '0; peak_index <= '0; peak_corr_re <= '0;
            peak_corr_im <= '0; peak_energy <= '0; search_error <= 1'b0;
            wr_ptr <= '0; candidate <= '0;
            offset <= '0; base_index_reg <= '0; timeout_count <= '0;
            corr_re <= '0; corr_im <= '0; energy_acc <= '0;
            prod_re_reg <= '0; prod_im_reg <= '0; pow_reg <= '0;
            best_mag <= '0; best_candidate <= '0; best_re <= '0; best_im <= '0;
            best_energy <= '0; eval_mag <= '0; eval_re <= '0; eval_im <= '0;
            eval_energy <= '0;
        end else begin
            peak_valid <= 1'b0;
            // The inferred RAM read port is clocked in SCAN_REQ.  The
            // following SCAN_ACC cycle consumes this registered word.

            if (state != IDLE)
                timeout_count <= timeout_count + 1'b1;

            if (state != IDLE && timeout_count >= TW'(TIMEOUT_CYCLES-1)) begin
                state <= IDLE; search_busy <= 1'b0; search_error <= 1'b1;
            end else begin
                case (state)
                    IDLE: begin
                        search_busy <= 1'b0;
                        if (search_start) begin
                            search_busy <= 1'b1; search_error <= 1'b0;
                            base_index_reg <= (ABSOLUTE_INDEX!=0)?sample_index_abs:search_base_index; wr_ptr <= '0;
                            timeout_count <= '0;
                            if (sample_valid) begin
                                wr_ptr <= (BUF_LEN == 1) ? '0 : 1;
                                if (BUF_LEN == 1) begin
                                    candidate <= '0; offset <= '0; corr_re <= '0;
                                    corr_im <= '0; energy_acc <= '0; best_mag <= '0;
                                    state <= SCAN_REQ;
                                end else state <= CAPTURE;
                            end else state <= CAPTURE;
                        end
                    end
                    CAPTURE: begin
                        if (search_start) search_error <= 1'b1;
                        if (sample_valid) begin
                            if (wr_ptr == PTR_W'(BUF_LEN-1)) begin
                                candidate <= '0; offset <= '0; corr_re <= '0;
                                corr_im <= '0; energy_acc <= '0; best_mag <= '0;
                                state <= SCAN_REQ;
                            end else wr_ptr <= wr_ptr + 1'b1;
                        end
                    end
                    SCAN_REQ: begin
                        state <= SCAN_ACC;
                    end
                    SCAN_ACC: begin
                        // Register the multiplier output.  The following
                        // MAC_ADD state performs the 48-bit accumulation in
                        // a separate cycle, isolating BRAM->DSP->carry paths.
                        prod_re_reg <= prod_re_ext;
                        prod_im_reg <= prod_im_ext;
                        // Energy is diagnostic in this matcher.  Dropping
                        // eight LSBs keeps the accumulator short and removes
                        // a long carry chain from the sample-rate path.
                        if (TRACK_ENERGY != 0) pow_reg <= sample_pow_scaled;
                        else pow_reg <= '0;
                        state <= MAC_ADD;
                    end
                    MAC_ADD: begin
                        corr_re <= corr_re + prod_re_reg;
                        corr_im <= corr_im + prod_im_reg;
                        if (TRACK_ENERGY != 0) energy_acc <= energy_acc + pow_reg;
                        else energy_acc <= '0;
                        if (offset == OW'(NFFT-1)) begin
                            state <= EVAL;
                        end else begin
                            offset <= offset + 1'b1;
                            state <= SCAN_REQ;
                        end
                    end
                    EVAL: begin
                        // Register the expensive magnitude before the
                        // compare/max tree.  This breaks the DSP-square to
                        // peak-index timing path at the 122.88 MHz clock.
                        eval_mag <= corr_mag;
                        eval_re <= corr_re; eval_im <= corr_im;
                        eval_energy <= {{(48-ENERGY_ACC_W){1'b0}},energy_acc};
                        state <= EVAL2;
                    end
                    EVAL2: begin
                        if (eval_mag >= best_mag) begin
                            best_mag <= eval_mag;
                            best_candidate <= candidate;
                            best_re <= eval_re; best_im <= eval_im;
                            best_energy <= eval_energy;
                        end
                        if (candidate == CW'(CANDIDATES-1)) begin
                            // Include the final candidate in the reported
                            // result when it wins the comparison this cycle.
                            if (eval_mag >= best_mag) begin
                                peak_score <= score_from_mag;
                                peak_index <= base_index_reg + INDEX_W'(candidate);
                                peak_corr_re <= eval_re; peak_corr_im <= eval_im;
                                peak_energy <= eval_energy;
                            end else begin
                                peak_score <= (best_mag >> RAW_SCORE_SHIFT > 65535) ? 16'hffff : 16'(best_mag >> RAW_SCORE_SHIFT);
                                peak_index <= base_index_reg + INDEX_W'(best_candidate);
                                peak_corr_re <= best_re; peak_corr_im <= best_im;
                                peak_energy <= best_energy;
                            end
                            peak_valid <= 1'b1; search_busy <= 1'b0; state <= IDLE;
                        end else begin
                            candidate <= candidate + 1'b1; offset <= '0;
                            corr_re <= '0; corr_im <= '0; energy_acc <= '0;
                            state <= SCAN_REQ;
                        end
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
