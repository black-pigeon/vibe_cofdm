`timescale 1ns/1ps
// Generated from +cofdm/ldpc_code.m: 12x24 base matrix, Z=27.
module cofdm_qcldpc_qc_base_rom(input wire [6:0] addr, output reg valid, output reg [4:0] var_block, output reg [4:0] shift);
always @* begin valid=1'b0; var_block=5'd0; shift=5'd0; case(addr)
7'd0: begin valid=1'b1; var_block=5'd0; shift=5'd0; end
7'd1: begin valid=1'b1; var_block=5'd4; shift=5'd0; end
7'd2: begin valid=1'b1; var_block=5'd5; shift=5'd0; end
7'd3: begin valid=1'b1; var_block=5'd8; shift=5'd0; end
7'd4: begin valid=1'b1; var_block=5'd11; shift=5'd0; end
7'd5: begin valid=1'b1; var_block=5'd12; shift=5'd1; end
7'd6: begin valid=1'b1; var_block=5'd13; shift=5'd0; end
7'd7: begin valid=1'b0; end
7'd8: begin valid=1'b1; var_block=5'd0; shift=5'd22; end
7'd9: begin valid=1'b1; var_block=5'd1; shift=5'd0; end
7'd10: begin valid=1'b1; var_block=5'd4; shift=5'd17; end
7'd11: begin valid=1'b1; var_block=5'd6; shift=5'd0; end
7'd12: begin valid=1'b1; var_block=5'd7; shift=5'd0; end
7'd13: begin valid=1'b1; var_block=5'd8; shift=5'd12; end
7'd14: begin valid=1'b1; var_block=5'd13; shift=5'd0; end
7'd15: begin valid=1'b1; var_block=5'd14; shift=5'd0; end
7'd16: begin valid=1'b1; var_block=5'd0; shift=5'd6; end
7'd17: begin valid=1'b1; var_block=5'd2; shift=5'd0; end
7'd18: begin valid=1'b1; var_block=5'd4; shift=5'd10; end
7'd19: begin valid=1'b1; var_block=5'd8; shift=5'd24; end
7'd20: begin valid=1'b1; var_block=5'd10; shift=5'd0; end
7'd21: begin valid=1'b1; var_block=5'd14; shift=5'd0; end
7'd22: begin valid=1'b1; var_block=5'd15; shift=5'd0; end
7'd23: begin valid=1'b0; end
7'd24: begin valid=1'b1; var_block=5'd0; shift=5'd2; end
7'd25: begin valid=1'b1; var_block=5'd3; shift=5'd0; end
7'd26: begin valid=1'b1; var_block=5'd4; shift=5'd20; end
7'd27: begin valid=1'b1; var_block=5'd8; shift=5'd25; end
7'd28: begin valid=1'b1; var_block=5'd9; shift=5'd0; end
7'd29: begin valid=1'b1; var_block=5'd15; shift=5'd0; end
7'd30: begin valid=1'b1; var_block=5'd16; shift=5'd0; end
7'd31: begin valid=1'b0; end
7'd32: begin valid=1'b1; var_block=5'd0; shift=5'd23; end
7'd33: begin valid=1'b1; var_block=5'd4; shift=5'd3; end
7'd34: begin valid=1'b1; var_block=5'd8; shift=5'd0; end
7'd35: begin valid=1'b1; var_block=5'd10; shift=5'd9; end
7'd36: begin valid=1'b1; var_block=5'd11; shift=5'd11; end
7'd37: begin valid=1'b1; var_block=5'd16; shift=5'd0; end
7'd38: begin valid=1'b1; var_block=5'd17; shift=5'd0; end
7'd39: begin valid=1'b0; end
7'd40: begin valid=1'b1; var_block=5'd0; shift=5'd24; end
7'd41: begin valid=1'b1; var_block=5'd2; shift=5'd23; end
7'd42: begin valid=1'b1; var_block=5'd3; shift=5'd1; end
7'd43: begin valid=1'b1; var_block=5'd4; shift=5'd17; end
7'd44: begin valid=1'b1; var_block=5'd6; shift=5'd3; end
7'd45: begin valid=1'b1; var_block=5'd8; shift=5'd10; end
7'd46: begin valid=1'b1; var_block=5'd17; shift=5'd0; end
7'd47: begin valid=1'b1; var_block=5'd18; shift=5'd0; end
7'd48: begin valid=1'b1; var_block=5'd0; shift=5'd25; end
7'd49: begin valid=1'b1; var_block=5'd4; shift=5'd8; end
7'd50: begin valid=1'b1; var_block=5'd8; shift=5'd7; end
7'd51: begin valid=1'b1; var_block=5'd9; shift=5'd18; end
7'd52: begin valid=1'b1; var_block=5'd12; shift=5'd0; end
7'd53: begin valid=1'b1; var_block=5'd18; shift=5'd0; end
7'd54: begin valid=1'b1; var_block=5'd19; shift=5'd0; end
7'd55: begin valid=1'b0; end
7'd56: begin valid=1'b1; var_block=5'd0; shift=5'd13; end
7'd57: begin valid=1'b1; var_block=5'd1; shift=5'd24; end
7'd58: begin valid=1'b1; var_block=5'd4; shift=5'd0; end
7'd59: begin valid=1'b1; var_block=5'd6; shift=5'd8; end
7'd60: begin valid=1'b1; var_block=5'd8; shift=5'd6; end
7'd61: begin valid=1'b1; var_block=5'd19; shift=5'd0; end
7'd62: begin valid=1'b1; var_block=5'd20; shift=5'd0; end
7'd63: begin valid=1'b0; end
7'd64: begin valid=1'b1; var_block=5'd0; shift=5'd7; end
7'd65: begin valid=1'b1; var_block=5'd1; shift=5'd20; end
7'd66: begin valid=1'b1; var_block=5'd3; shift=5'd16; end
7'd67: begin valid=1'b1; var_block=5'd4; shift=5'd22; end
7'd68: begin valid=1'b1; var_block=5'd5; shift=5'd10; end
7'd69: begin valid=1'b1; var_block=5'd8; shift=5'd23; end
7'd70: begin valid=1'b1; var_block=5'd20; shift=5'd0; end
7'd71: begin valid=1'b1; var_block=5'd21; shift=5'd0; end
7'd72: begin valid=1'b1; var_block=5'd0; shift=5'd11; end
7'd73: begin valid=1'b1; var_block=5'd4; shift=5'd19; end
7'd74: begin valid=1'b1; var_block=5'd8; shift=5'd13; end
7'd75: begin valid=1'b1; var_block=5'd10; shift=5'd3; end
7'd76: begin valid=1'b1; var_block=5'd11; shift=5'd17; end
7'd77: begin valid=1'b1; var_block=5'd21; shift=5'd0; end
7'd78: begin valid=1'b1; var_block=5'd22; shift=5'd0; end
7'd79: begin valid=1'b0; end
7'd80: begin valid=1'b1; var_block=5'd0; shift=5'd25; end
7'd81: begin valid=1'b1; var_block=5'd2; shift=5'd8; end
7'd82: begin valid=1'b1; var_block=5'd4; shift=5'd23; end
7'd83: begin valid=1'b1; var_block=5'd5; shift=5'd18; end
7'd84: begin valid=1'b1; var_block=5'd7; shift=5'd14; end
7'd85: begin valid=1'b1; var_block=5'd8; shift=5'd9; end
7'd86: begin valid=1'b1; var_block=5'd22; shift=5'd0; end
7'd87: begin valid=1'b1; var_block=5'd23; shift=5'd0; end
7'd88: begin valid=1'b1; var_block=5'd0; shift=5'd3; end
7'd89: begin valid=1'b1; var_block=5'd4; shift=5'd16; end
7'd90: begin valid=1'b1; var_block=5'd7; shift=5'd2; end
7'd91: begin valid=1'b1; var_block=5'd8; shift=5'd25; end
7'd92: begin valid=1'b1; var_block=5'd9; shift=5'd5; end
7'd93: begin valid=1'b1; var_block=5'd12; shift=5'd1; end
7'd94: begin valid=1'b1; var_block=5'd23; shift=5'd0; end
7'd95: begin valid=1'b0; end
default: begin end
endcase
end
endmodule
