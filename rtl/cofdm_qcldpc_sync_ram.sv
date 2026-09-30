`timescale 1ns/1ps
// Small synchronous single-clock RAM used as one bank of the QC decoder.
// The write and read requests are mutually exclusive in the decoder schedule;
// the template is nevertheless written in a form Vivado can map to BRAM.
module cofdm_qcldpc_sync_ram #(
    parameter integer DEPTH=72,
    parameter integer DATA_W=9,
    parameter integer ADDR_W=$clog2(DEPTH)
)(
    input wire clk, input wire rst,
    input wire wr_en, input wire [ADDR_W-1:0] wr_addr,
    input wire signed [DATA_W-1:0] wr_data,
    input wire rd_en, input wire [ADDR_W-1:0] rd_addr,
    output reg signed [DATA_W-1:0] rd_data
);
    (* ram_style="block" *) reg signed [DATA_W-1:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        if (rst) rd_data <= '0;
        else if (rd_en) rd_data <= mem[rd_addr];
    end
endmodule
