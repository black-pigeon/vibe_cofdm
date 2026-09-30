`timescale 1ns/1ps
// 32-bit simple-dual-port sample buffer.  The COFDM_XILINX_RAMB build uses
// one RAMB36E1; the default branch is an equivalent behavioral model for
// Icarus/Verilator unit tests.
module cofdm_ltf_sample_buffer #(
    parameter integer ADDR_W = 9,
    parameter integer DEPTH = (1 << ADDR_W)
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   wr_en,
    input  wire [ADDR_W-1:0]     wr_addr,
    input  wire [31:0]            wr_data,
    input  wire                   rd_en,
    input  wire [ADDR_W-1:0]     rd_addr,
    output wire signed [31:0]     rd_data
);
`ifdef COFDM_XILINX_RAMB
    wire [31:0] bram_do;
    wire unused_cascade_a, unused_cascade_b, unused_dbiterr, unused_sbiterr;
    wire [7:0] unused_eccparity;
    wire [8:0] unused_rdaddrecc;
    RAMB36E1 #(
        .RAM_MODE("TDP"),
        .READ_WIDTH_A(36),
        .WRITE_WIDTH_B(36),
        .DOA_REG(0),
        .DOB_REG(0),
        .WRITE_MODE_A("WRITE_FIRST"),
        .WRITE_MODE_B("WRITE_FIRST")
    ) u_ramb36 (
        .CASCADEOUTA(unused_cascade_a), .CASCADEOUTB(unused_cascade_b),
        .DBITERR(unused_dbiterr), .DOADO(bram_do), .DOBDO(),
        .DOPADOP(), .DOPBDOP(), .ECCPARITY(unused_eccparity),
        .RDADDRECC(unused_rdaddrecc), .SBITERR(unused_sbiterr),
        .ADDRARDADDR({2'b0,rd_addr,5'b0}), .ADDRBWRADDR({2'b0,wr_addr,5'b0}),
        .CASCADEINA(1'b0), .CASCADEINB(1'b0),
        .CLKARDCLK(clk), .CLKBWRCLK(clk),
        .DIADI(32'b0), .DIBDI(wr_data), .DIPADIP(4'b0), .DIPBDIP(4'b0),
        .ENARDEN(rd_en), .ENBWREN(wr_en),
        .INJECTDBITERR(1'b0), .INJECTSBITERR(1'b0),
        .REGCEAREGCE(1'b1), .REGCEB(1'b1),
        .RSTRAMARSTRAM(rst), .RSTRAMB(rst),
        .RSTREGARSTREG(rst), .RSTREGB(rst),
        .WEA(4'b0000), .WEBWE(wr_en ? 8'h0f : 8'h00)
    );
    assign rd_data = $signed(bram_do);
`else
    (* ram_style = "block" *) reg signed [31:0] mem [0:DEPTH-1];
    reg signed [31:0] rd_reg;
    assign rd_data = rd_reg;
    always @(posedge clk) begin
        if (rst) begin
            rd_reg <= '0;
        end else begin
            if (wr_en) mem[wr_addr] <= wr_data;
            if (rd_en) rd_reg <= mem[rd_addr];
        end
    end
`endif
endmodule
