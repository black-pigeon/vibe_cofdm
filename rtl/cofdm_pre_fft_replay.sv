`timescale 1ns/1ps
// Replays the corrected time-domain samples selected by the LTF detector.
//
// The TDM LTF matcher finishes after the live stream has already passed the
// two training symbols.  A circular BRAM therefore sits between acquisition
// and XFFT.  Once a peak is confirmed, this block replays
//
//   LTF1 CP + useful, LTF2 CP + useful, then DATA_SYMBOLS symbols
//
// with one sample per clock after the synchronous BRAM read pipeline.  The
// output marker is the first CP sample of every symbol and can be connected
// directly to cofdm_fft_stream_frontend.in_symbol_start.  PEAK_TO_BUFFER_OFFSET
// is a calibration term for the sample-index convention used by the detector.
module cofdm_pre_fft_replay #(
    parameter integer IW = 16,
    parameter integer NFFT = 256,
    parameter integer CP_LEN = 32,
    parameter integer TRAINING_SYMBOLS = 2,
    parameter integer DATA_SYMBOLS = 0,
    parameter integer BUFFER_DEPTH = 4096,
    parameter integer INDEX_W = 32,
    parameter integer PEAK_TO_BUFFER_OFFSET = 0
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         sample_valid,
    input  wire signed [IW-1:0]         sample_re,
    input  wire signed [IW-1:0]         sample_im,
    input  wire                         peak_valid,
    input  wire [INDEX_W-1:0]            peak_index,
    output wire                         out_valid,
    input  wire                         out_ready,
    output wire signed [IW-1:0]         out_re,
    output wire signed [IW-1:0]         out_im,
    output wire                         out_symbol_start,
    output wire [7:0]                   out_symbol_index,
    output wire [1:0]                   out_symbol_kind,
    output wire                         replay_busy,
    output wire                         replay_done,
    output wire                         replay_error,
    output wire [INDEX_W-1:0]            replay_start_index
);
    localparam integer ADDR_W = (BUFFER_DEPTH < 2) ? 1 : $clog2(BUFFER_DEPTH);
    localparam integer SPAN = NFFT + CP_LEN;
    localparam integer SYMBOLS = TRAINING_SYMBOLS + DATA_SYMBOLS;
    localparam integer TOTAL = SPAN * SYMBOLS;
    localparam integer OFF_W = (TOTAL < 2) ? 1 : $clog2(TOTAL);
    localparam [OFF_W-1:0] LAST_OFFSET = OFF_W'(TOTAL-1);

    initial begin
        if (BUFFER_DEPTH < TOTAL + CP_LEN)
            $error("cofdm_pre_fft_replay BUFFER_DEPTH is too small for replay");
        if ((BUFFER_DEPTH & (BUFFER_DEPTH-1)) != 0)
            $error("cofdm_pre_fft_replay BUFFER_DEPTH must be a power of two");
    end

    reg [INDEX_W-1:0] write_count;
    wire [ADDR_W-1:0] write_addr = write_count[ADDR_W-1:0];
    reg mem_pending;
    reg [OFF_W-1:0] issue_offset, pending_offset, rd_offset;
    wire [ADDR_W-1:0] issue_addr = start_index_reg[ADDR_W-1:0] + ADDR_W'(issue_offset);
    wire slot_available = !rd_valid || out_ready;
    wire issue_fire = (state == S_READ) && slot_available &&
                      (issue_offset <= LAST_OFFSET);
    wire [31:0] mem_rd_data;
    cofdm_pre_fft_replay_mem #(.ADDR_W(ADDR_W),.DEPTH(BUFFER_DEPTH)) u_mem (
      .clk,.rst,.wr_en(sample_valid),.wr_addr(write_addr),
      .wr_data({sample_im,sample_re}),.rd_en(issue_fire),
      .rd_addr(issue_addr),.rd_data(mem_rd_data));

    localparam [1:0] S_IDLE=2'd0, S_WAIT=2'd1, S_READ=2'd2;
    reg [1:0] state;
    reg [INDEX_W-1:0] start_index_reg;
    reg rd_valid;
    reg signed [IW-1:0] rd_re, rd_im;
    reg rd_symbol_start;
    reg [7:0] rd_symbol_index;
    reg [1:0] rd_symbol_kind;
    reg done_pulse;
    reg error_reg;

    wire [INDEX_W-1:0] total_end_index = start_index_reg + INDEX_W'(TOTAL);
    wire enough_captured = (write_count >= total_end_index);
    wire retained = (write_count >= start_index_reg) &&
                    ((write_count - start_index_reg) <= INDEX_W'(BUFFER_DEPTH));
    wire [31:0] pending_offset_ext = 32'(pending_offset);
    wire [31:0] pending_symbol_number = pending_offset_ext / SPAN;

    assign out_valid = rd_valid;
    assign out_re = rd_re;
    assign out_im = rd_im;
    assign out_symbol_start = rd_valid && rd_symbol_start;
    assign out_symbol_index = rd_symbol_index;
    assign out_symbol_kind = rd_symbol_kind;
    assign replay_busy = (state != S_IDLE) || rd_valid;
    assign replay_done = done_pulse;
    assign replay_error = error_reg;
    assign replay_start_index = start_index_reg;

    function automatic [1:0] symbol_kind(input [31:0] n);
        begin
            if (n < TRAINING_SYMBOLS) symbol_kind = n[1:0];
            else symbol_kind = 2'd2; // data/header symbol
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            write_count <= '0;
            state <= S_IDLE;
            start_index_reg <= '0;
            issue_offset <= '0; pending_offset <= '0; rd_offset <= '0;
            mem_pending <= 1'b0;
            rd_valid <= 1'b0;
            rd_re <= '0; rd_im <= '0;
            rd_symbol_start <= 1'b0;
            rd_symbol_index <= '0; rd_symbol_kind <= '0;
            done_pulse <= 1'b0;
            error_reg <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            if (sample_valid) begin
                write_count <= write_count + 1'b1;
            end

            if (peak_valid && state == S_IDLE) begin
                // The detector reports the useful LTF index. Replay starts at
                // the CP immediately preceding LTF1.
                start_index_reg <= peak_index + INDEX_W'(PEAK_TO_BUFFER_OFFSET-CP_LEN);
                rd_offset <= '0;
                error_reg <= 1'b0;
                state <= S_WAIT;
            end

            case (state)
                S_WAIT: begin
                    if (!retained && write_count > start_index_reg)
                        error_reg <= 1'b1;
                    if (enough_captured && retained) begin
                        rd_valid <= 1'b0;
                        issue_offset <= '0;
                        pending_offset <= '0;
                        rd_offset <= '0;
                        mem_pending <= 1'b0;
                        state <= S_READ;
                    end
                end
                S_READ: begin
                    if (mem_pending && slot_available) begin
                        rd_re <= mem_rd_data[IW-1:0];
                        rd_im <= mem_rd_data[2*IW-1:IW];
                        rd_symbol_start <= ((pending_offset_ext % SPAN) == 0);
                        rd_symbol_index <= pending_symbol_number[7:0];
                        rd_symbol_kind <= symbol_kind(pending_symbol_number);
                        rd_offset <= pending_offset;
                        rd_valid <= 1'b1;
                    end
                    if (issue_fire) begin
                        pending_offset <= issue_offset;
                        issue_offset <= issue_offset + OFF_W'(1);
                        mem_pending <= 1'b1;
                    end else if (mem_pending && slot_available) begin
                        mem_pending <= 1'b0;
                    end
                    if (rd_valid && out_ready) begin
                        if (rd_offset == LAST_OFFSET) begin
                            rd_valid <= 1'b0;
                            state <= S_IDLE;
                            done_pulse <= 1'b1;
                        end
                    end
                end
                default: begin end
            endcase
        end
    end
endmodule
