`timescale 1ns/1ps
// Eight PRBS bits per symbol, in MATLAB signed-carrier order. Includes a
// skipped group for each midamble. Call advance exactly once per non-LTF
// symbol (header/data/midamble), after consuming its pilot signs.
module cofdm_symbol_pilots(
    input wire clk,rst,frame_start,advance,
    input wire [7:0] fft_bin,
    output reg pilot_sign
);
    reg [6:0] state;
    reg [6:0] next_state;
    reg [7:0] signs;
    integer k;
    always @* begin
        next_state=state;
        for(k=0;k<8;k=k+1) begin
            signs[k]=next_state[0];
            next_state={next_state[0]^next_state[3],next_state[6:1]};
        end
        case(fft_bin)
            165:pilot_sign=signs[0]; 191:pilot_sign=signs[1];
            217:pilot_sign=signs[2]; 243:pilot_sign=signs[3];
            13:pilot_sign=signs[4]; 39:pilot_sign=signs[5];
            65:pilot_sign=signs[6]; 91:pilot_sign=signs[7];
            default:pilot_sign=0;
        endcase
    end
    always @(posedge clk) begin
        if(rst || frame_start) state<=7'd53;
        else if(advance) state<=next_state;
    end
endmodule
