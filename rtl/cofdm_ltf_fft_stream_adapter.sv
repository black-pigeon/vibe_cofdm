`timescale 1ns/1ps
// Adds the metadata that the XFFT stream does not carry in this project.
// XFFT output may contain valid bubbles; bin_count and frame_id advance only
// on valid&&ready.  Two consecutive frames are labelled LTF1 (symbol_id=0)
// and LTF2 (symbol_id=1), then the label toggles for the next pair.
module cofdm_ltf_fft_stream_adapter #(
    parameter integer NFFT = 256,
    parameter [NFFT-1:0] ACTIVE_MASK = {NFFT{1'b1}}
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire                         s_last,
    input  wire signed [15:0]           s_re,
    input  wire signed [15:0]           s_im,
    output wire                         m_valid,
    output wire                         m_symbol_start,
    output wire                         m_symbol_id,
    output wire                         m_last,
    output wire [$clog2(NFFT)-1:0]      m_bin_index,
    output wire                         m_bin_active,
    output wire signed [15:0]           m_re,
    output wire signed [15:0]           m_im,
    output reg                          frame_error
);
    localparam integer BIN_W = (NFFT < 2) ? 1 : $clog2(NFFT);
    localparam [BIN_W-1:0] LAST_BIN = BIN_W'(NFFT-1);
    reg [BIN_W-1:0] bin_count;
    reg symbol_id_reg;
    wire accept = s_valid && s_ready;

    // The accumulator is a one-cycle consumer with no backpressure.  Keep
    // ready asserted so an XFFT output bubble never becomes an artificial
    // sample or changes the bin numbering.
    assign s_ready = 1'b1;
    assign m_valid = accept;
    assign m_symbol_start = accept && (bin_count == {BIN_W{1'b0}});
    assign m_symbol_id = symbol_id_reg;
    assign m_last = accept && s_last;
    assign m_bin_index = bin_count;
    assign m_bin_active = ACTIVE_MASK[bin_count];
    assign m_re = s_re;
    assign m_im = s_im;

    always @(posedge clk) begin
        if (rst) begin
            bin_count <= '0;
            symbol_id_reg <= 1'b0;
            frame_error <= 1'b0;
        end else if (accept) begin
            if (s_last) begin
                // A legal frame ends on bin NFFT-1.  Keep running after the
                // second frame so this block can be reused for later headers.
                if (bin_count != LAST_BIN)
                    frame_error <= 1'b1;
                bin_count <= '0;
                symbol_id_reg <= ~symbol_id_reg;
            end else if (bin_count == LAST_BIN) begin
                // Protect against a missing TLAST: discard the stale count,
                // flag the framing error, and begin the next frame cleanly.
                frame_error <= 1'b1;
                bin_count <= '0;
                symbol_id_reg <= ~symbol_id_reg;
            end else begin
                bin_count <= bin_count + 1'b1;
            end
        end
    end
endmodule
