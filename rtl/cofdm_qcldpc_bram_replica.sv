`timescale 1ns/1ps
// One synchronous-write/synchronous-read BRAM replica used by the codeword
// scheduler. The scheduler instantiates one replica per decoder lane, so each
// lane has an independent read port and no run-time multi-read mux tree.
module cofdm_qcldpc_bram_replica #(
    parameter integer DEPTH=6480,
    parameter integer DATA_W=7,
    parameter integer ADDR_W=$clog2(DEPTH)
)(
    input wire clk, input wire rst,
    input wire wr_en, input wire [ADDR_W-1:0] wr_addr,
    input wire signed [DATA_W-1:0] wr_data,
    input wire rd_en, input wire [ADDR_W-1:0] rd_addr,
    output wire signed [DATA_W-1:0] rd_data
);
`ifdef COFDM_XILINX_RAMB
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(ADDR_W), .ADDR_WIDTH_B(ADDR_W),
        .BYTE_WRITE_WIDTH_A(DATA_W), .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"), .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(DATA_W*DEPTH), .READ_DATA_WIDTH_B(DATA_W),
        .READ_LATENCY_B(1), .READ_RESET_VALUE_B("0"),
        .RST_MODE_B("SYNC"), .SIM_ASSERT_CHK(0), .USE_MEM_INIT(0),
        .WRITE_DATA_WIDTH_A(DATA_W)
    ) u_mem (
        .sleep(1'b0), .clka(clk), .ena(wr_en), .wea(wr_en),
        .addra(wr_addr), .dina(wr_data),
        .injectsbiterra(1'b0), .injectdbiterra(1'b0),
        .clkb(clk), .rstb(rst), .enb(rd_en), .regceb(1'b1),
        .addrb(rd_addr), .doutb(rd_data), .sbiterrb(), .dbiterrb()
    );
`else
    (* ram_style="block" *) reg signed [DATA_W-1:0] mem [0:DEPTH-1];
    reg signed [DATA_W-1:0] rd_data_r;
    assign rd_data=rd_data_r;
    always @(posedge clk) begin
        if(wr_en) mem[wr_addr]<=wr_data;
        if(rst) rd_data_r<='0;
        else if(rd_en) rd_data_r<=mem[rd_addr];
    end
`endif
endmodule
