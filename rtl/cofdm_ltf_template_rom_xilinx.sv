`timescale 1ns/1ps
// Vivado blk_mem_gen wrapper for the 256x32 complex LTF template ROM.
// COE word format: [31:16] = signed Q1.15 Re, [15:0] = signed Q1.15 Im.
module cofdm_ltf_template_rom_xilinx (
    input  wire               clk,
    input  wire [7:0]         addr,
    output wire signed [15:0] re,
    output wire signed [15:0] im
);
    wire [31:0] dout;
    cofdm_ltf_template_rom_ip u_ip (
        .clka(clk), .addra(addr), .douta(dout)
    );
    assign re = $signed(dout[31:16]);
    assign im = $signed(dout[15:0]);
endmodule
