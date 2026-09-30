`timescale 1ns/1ps
// Bounded soft-input FIFO. Vivado uses an XPM BRAM FIFO with FWFT semantics;
// portable simulation uses the same handshake with behavioral memory.
module cofdm_llr_fifo #(parameter integer WIDTH=20,DEPTH=1024)(
    input wire clk,rst,
    input wire in_valid,output wire in_ready,input wire [WIDTH-1:0] in_data,
    output wire out_valid,input wire out_ready,output wire [WIDTH-1:0] out_data
);
    reg [4:0] reset_hold;
    always @(posedge clk) begin
        if(rst) reset_hold<=5'b11111;
        else reset_hold<={reset_hold[3:0],1'b0};
    end
    wire fifo_rst=rst || (|reset_hold);
`ifdef COFDM_XILINX_FIFO
    wire full,empty,wr_busy,rd_busy;
    assign in_ready=!full && !wr_busy && !fifo_rst;
    assign out_valid=!empty && !rd_busy && !fifo_rst;
    xpm_fifo_sync #(.FIFO_MEMORY_TYPE("block"),.FIFO_WRITE_DEPTH(DEPTH),
        .WRITE_DATA_WIDTH(WIDTH),.READ_DATA_WIDTH(WIDTH),.READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),.ECC_MODE("no_ecc"),.USE_ADV_FEATURES("0000"),
        .DOUT_RESET_VALUE("0"),.FULL_RESET_VALUE(0),.WAKEUP_TIME(0)) storage(
        .wr_clk(clk),.rst(fifo_rst),.sleep(1'b0),.wr_en(in_valid && in_ready),.din(in_data),
        .full,.wr_rst_busy(wr_busy),.rd_en(out_valid && out_ready),.dout(out_data),
        .empty,.rd_rst_busy(rd_busy),.injectsbiterr(1'b0),.injectdbiterr(1'b0),
        .almost_empty(),.almost_full(),.data_valid(),.dbiterr(),.overflow(),
        .prog_empty(),.prog_full(),.rd_data_count(),.sbiterr(),.underflow(),
        .wr_ack(),.wr_data_count());
`else
    localparam integer AW=$clog2(DEPTH);
    reg [WIDTH-1:0] mem[0:DEPTH-1];
    reg [AW-1:0] wr,rd;
    reg [AW:0] count;
    wire push=in_valid && in_ready,pop=out_valid && out_ready;
    assign in_ready=(count<DEPTH) && !fifo_rst;
    assign out_valid=(count!=0) && !fifo_rst;
    assign out_data=mem[rd];
    initial if(DEPTH<16 || (2**AW)!=DEPTH) $error("FIFO requires power-of-two depth >=16");
    always @(posedge clk) begin
        if(fifo_rst) begin wr<=0;rd<=0;count<=0;end
        else begin
            if(push) begin mem[wr]<=in_data;wr<=wr+1'b1;end
            if(pop) rd<=rd+1'b1;
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
        end
    end
`endif
endmodule
