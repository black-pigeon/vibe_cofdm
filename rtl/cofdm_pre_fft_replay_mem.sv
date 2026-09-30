`timescale 1ns/1ps
// Single-clock simple-dual-port memory used by the pre-FFT replay buffer.
// The Xilinx branch explicitly banks RAMB36E1 primitives (32-bit data,
// 1024 words per bank); the behavioral branch is used by Icarus/Verilator.
module cofdm_pre_fft_replay_mem #(
    parameter integer ADDR_W = 13,
    parameter integer DEPTH = (1 << ADDR_W)
) (
    input wire clk,
    input wire rst,
    input wire wr_en,
    input wire [ADDR_W-1:0] wr_addr,
    input wire [31:0] wr_data,
    input wire rd_en,
    input wire [ADDR_W-1:0] rd_addr,
    output wire [31:0] rd_data
);
`ifdef COFDM_XILINX_RAMB
    localparam integer BANKS = (DEPTH + 1023) / 1024;
    wire [31:0] bank_do [0:BANKS-1];
    wire [BANKS-1:0] bank_rd_en;
    wire [BANKS-1:0] bank_wr_en;
    genvar b;
    generate for (b=0; b<BANKS; b=b+1) begin : gen_bank
        assign bank_rd_en[b] = rd_en && ((rd_addr >> 10) == b);
        assign bank_wr_en[b] = wr_en && ((wr_addr >> 10) == b);
        RAMB36E1 #(
          .RAM_MODE("TDP"), .READ_WIDTH_A(36), .WRITE_WIDTH_B(36),
          .DOA_REG(0), .DOB_REG(0), .WRITE_MODE_A("WRITE_FIRST"),
          .WRITE_MODE_B("WRITE_FIRST")
        ) u_ramb36 (
          .CASCADEOUTA(), .CASCADEOUTB(), .DBITERR(), .DOADO(bank_do[b]),
          .DOBDO(), .DOPADOP(), .DOPBDOP(), .ECCPARITY(), .RDADDRECC(),
          .SBITERR(), .ADDRARDADDR({1'b0,rd_addr[9:0],5'b0}),
          .ADDRBWRADDR({1'b0,wr_addr[9:0],5'b0}), .CASCADEINA(1'b0),
          .CASCADEINB(1'b0), .CLKARDCLK(clk), .CLKBWRCLK(clk),
          .DIADI(32'b0), .DIBDI(wr_data), .DIPADIP(4'b0), .DIPBDIP(4'b0),
          .ENARDEN(bank_rd_en[b]), .ENBWREN(bank_wr_en[b]),
          .INJECTDBITERR(1'b0), .INJECTSBITERR(1'b0), .REGCEAREGCE(1'b1),
          .REGCEB(1'b1), .RSTRAMARSTRAM(rst), .RSTRAMB(rst),
          .RSTREGARSTREG(rst), .RSTREGB(rst), .WEA(4'b0000),
          .WEBWE(bank_wr_en[b] ? 8'h0f : 8'h00)
        );
    end endgenerate
    reg [ADDR_W-1:0] bank_addr;
    always @(posedge clk) if(rd_en) bank_addr<=rd_addr;
    reg [31:0] rd_mux;
    integer i;
    always @* begin
        rd_mux = 32'b0;
        for (i=0; i<BANKS; i=i+1)
            if ((bank_addr >> 10) == i) rd_mux = bank_do[i];
    end
    assign rd_data = rd_mux;
`else
    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];
    reg [31:0] rd_reg;
    assign rd_data = rd_reg;
    always @(posedge clk) begin
        if (rst) rd_reg <= 32'b0;
        else begin
            if (wr_en) mem[wr_addr] <= wr_data;
            if (rd_en) rd_reg <= mem[rd_addr];
        end
    end
`endif
endmodule
