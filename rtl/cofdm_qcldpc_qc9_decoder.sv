`timescale 1ns/1ps
// First QC-subblock throughput implementation for the project (Z=27, P=9).
//
// Nine processing elements handle one third of a QC layer in parallel.  The
// implementation deliberately keeps the same quantized layered NMS arithmetic
// as cofdm_qcldpc_648_decoder so that it can be compared bit-for-bit before
// replacing the scalar bank.  The memories are written as explicit banks in a
// later integration step; this reference core focuses on the cycle schedule
// and arithmetic equivalence.
module cofdm_qcldpc_qc9_decoder #(
    parameter integer MAX_ITERS=12
)(
    input wire clk, input wire rst, input wire start,
    input wire in_valid, input wire in_last, output wire in_ready,
    input wire signed [6:0] in_llr,
    output wire out_valid, input wire out_ready,
    output wire out_last, output wire out_bit,
    output reg done, output reg decode_ok, output reg syndrome_ok,
    output reg [4:0] iterations_done, output reg frame_error,
    output wire busy
);
    /* verilator lint_off WIDTH */
    /* verilator lint_off UNUSED */
    localparam [3:0] IDLE=0, LOAD=1, QPASS=2, UPASS=3,
                     SYN=4, DECIDE=5, OUT=6;
    reg [3:0] state;
    reg [9:0] load_idx, out_idx;
    reg [3:0] layer;
    reg [1:0] group;
    reg [3:0] edge_idx;
    reg [4:0] iter;
    reg signed [8:0] post_mem [0:647];
    reg signed [6:0] msg_mem [0:2591];
    reg signed [8:0] q_cache [0:7][0:8];
    reg [8:0] min1 [0:8], min2 [0:8];
    reg [3:0] min_edge [0:8];
    reg sign_acc [0:8];
    reg synd_acc [0:8];
    reg bad_checks;

    wire base_valid;
    wire [4:0] base_var_block, base_shift;
    wire [6:0] base_addr = {layer,3'b000} + {3'b000,edge_idx};
    cofdm_qcldpc_qc_base_rom base_rom(
        .addr(base_addr), .valid(base_valid),
        .var_block(base_var_block), .shift(base_shift));

    integer l;
    integer check_pos_i, var_pos_i, var_addr_i, msg_addr_i;
    reg [9:0] var_addr_c [0:8];
    reg [11:0] msg_addr_c [0:8];
    reg signed [8:0] q_c [0:8];
    reg [8:0] q_mag_c [0:8];
    reg q_sign_c [0:8];
    reg signed [6:0] rnew_c [0:8];
    reg signed [8:0] post_new_c [0:8];
    reg [8:0] selected_mag_c [0:8];
    reg [7:0] scale_full_c [0:8];
    reg [5:0] scaled_mag_c [0:8];
    reg hard_c [0:8];
    reg group_bad_c;

    function automatic signed [8:0] sat9(input signed [10:0] x);
        begin
            if (x > 11'sd255) sat9=9'sd255;
            else if (x < -11'sd255) sat9=-9'sd255;
            else sat9=x[8:0];
        end
    endfunction
    function automatic [7:0] scale_min(input [8:0] x);
        begin scale_min=8'((({2'b0,x}<<1)+{2'b0,x}+11'd2)>>2); end
    endfunction

    // Address and arithmetic for all nine processing elements.  The modulo
    // operation is a constant Z=27 reduction and synthesizes to compare/subtract.
    always @* begin
        group_bad_c=1'b0;
        for (l=0;l<9;l=l+1) begin
            check_pos_i=group*9+l;
            var_pos_i=check_pos_i+base_shift;
            if (var_pos_i>=27) var_pos_i=var_pos_i-27;
            var_addr_i=base_var_block*27+var_pos_i;
            var_addr_c[l]=var_addr_i[9:0];
            // Keep the same edge ordering as the scalar decoder: each check
            // position owns eight message slots, even when the eighth slot is
            // padding for a degree-seven base row.
            msg_addr_i=layer*216+check_pos_i*8+edge_idx;
            msg_addr_c[l]=msg_addr_i[11:0];
            q_c[l]=sat9($signed({post_mem[var_addr_c[l]][8],post_mem[var_addr_c[l]]})-
                ((iter==0)?11'sd0:$signed({{4{msg_mem[msg_addr_c[l]][6]}},msg_mem[msg_addr_c[l]]})));
            q_mag_c[l]=q_c[l][8] ? $unsigned(-q_c[l]) : $unsigned(q_c[l]);
            q_sign_c[l]=q_c[l][8];
            selected_mag_c[l]=(min_edge[l]==edge_idx)?min2[l]:min1[l];
            scale_full_c[l]=scale_min(selected_mag_c[l]);
            scaled_mag_c[l]=(scale_full_c[l]>8'd63)?6'd63:scale_full_c[l][5:0];
            rnew_c[l]= (sign_acc[l]^q_cache[edge_idx[2:0]][l][8]) ?
                -$signed({1'b0,scaled_mag_c[l]}) : $signed({1'b0,scaled_mag_c[l]});
            post_new_c[l]=sat9($signed({q_cache[edge_idx[2:0]][l][8],q_cache[edge_idx[2:0]][l]})+
                $signed({{4{rnew_c[l][6]}},rnew_c[l]}));
            hard_c[l]=post_mem[var_addr_c[l]][8];
            if (state==SYN)
                group_bad_c=group_bad_c | (synd_acc[l] ^ (base_valid ? hard_c[l] : 1'b0));
        end
        // hard_c is XORed with the running syndrome in SYN.  Invalid padded
        // edges contribute nothing, so group_bad_c is formed in the sequential
        // block using the current synd_acc and hard_c values.
    end

    assign busy=(state!=IDLE);
    assign in_ready=(state==LOAD) && !rst;
    assign out_valid=(state==OUT);
    assign out_last=(state==OUT) && (out_idx==10'd323);
    assign out_bit=(state==OUT) ? post_mem[out_idx][8] : 1'b0;

    initial if(MAX_ITERS<1 || MAX_ITERS>31) $error("MAX_ITERS must be 1..31");

    always @(posedge clk) begin
        if (rst) begin
            state<=IDLE; load_idx<=0; out_idx<=0; layer<=0; group<=0; edge_idx<=0; iter<=0;
            done<=0; decode_ok<=0; syndrome_ok<=0; iterations_done<=0; frame_error<=0;
            bad_checks<=0;
            for (l=0;l<9;l=l+1) begin
                min1[l]<=9'd511; min2[l]<=9'd511; min_edge[l]<=0; sign_acc[l]<=0; synd_acc[l]<=0;
            end
        end else begin
            done<=0; frame_error<=0;
            case (state)
            IDLE: if (start) begin
                state<=LOAD; load_idx<=0; decode_ok<=0; syndrome_ok<=0; iterations_done<=0;
            end
            LOAD: if (in_valid) begin
                if (in_last != (load_idx==10'd647)) begin
                    frame_error<=1; state<=IDLE;
                end else begin
                    post_mem[load_idx] <= (in_llr==-7'sd64) ? -9'sd63 : $signed({{2{in_llr[6]}},in_llr});
                    if (load_idx==10'd647) begin
                        layer<=0; group<=0; edge_idx<=0; iter<=0; bad_checks<=0; state<=QPASS;
                        for (l=0;l<9;l=l+1) begin
                            min1[l]<=9'd511; min2[l]<=9'd511; min_edge[l]<=0; sign_acc[l]<=0;
                        end
                    end else load_idx<=load_idx+1'b1;
                end
            end
            QPASS: begin
                if (base_valid) begin
                    for (l=0;l<9;l=l+1) begin
                        q_cache[edge_idx[2:0]][l] <= q_c[l];
                        sign_acc[l] <= sign_acc[l] ^ q_sign_c[l];
                        if (q_mag_c[l] < min1[l]) begin
                            min2[l] <= min1[l]; min1[l] <= q_mag_c[l]; min_edge[l] <= edge_idx;
                        end else if (q_mag_c[l] < min2[l]) min2[l] <= q_mag_c[l];
                    end
                end
                if (edge_idx==4'd7) begin edge_idx<=0; state<=UPASS; end
                else edge_idx<=edge_idx+1'b1;
            end
            UPASS: begin
                if (base_valid) begin
                    for (l=0;l<9;l=l+1) begin
                        post_mem[var_addr_c[l]] <= post_new_c[l];
                        msg_mem[msg_addr_c[l]] <= rnew_c[l];
                    end
                end
                if (edge_idx==4'd7) begin
                    for (l=0;l<9;l=l+1) begin min1[l]<=9'd511; min2[l]<=9'd511; min_edge[l]<=0; sign_acc[l]<=0; end
                    if (group==2) begin
                        group<=0;
                        if (layer==11) begin layer<=0; edge_idx<=0; bad_checks<=0; for(l=0;l<9;l=l+1) synd_acc[l]<=0; state<=SYN; end
                        else begin layer<=layer+1'b1; edge_idx<=0; state<=QPASS; end
                    end else begin group<=group+1'b1; edge_idx<=0; state<=QPASS; end
                end else edge_idx<=edge_idx+1'b1;
            end
            SYN: begin
                if (base_valid) for (l=0;l<9;l=l+1) synd_acc[l]<=synd_acc[l]^hard_c[l];
                if (edge_idx==4'd7) begin
                    if (group==2) begin
                        // Include the current edge_idx in the final syndrome value.
                        bad_checks <= bad_checks | group_bad_c;
                        iterations_done<=iter+1'b1;
                        if (!(bad_checks | group_bad_c) || iter==5'(MAX_ITERS-1)) begin
                            decode_ok<=!(bad_checks | group_bad_c); syndrome_ok<=!(bad_checks | group_bad_c);
                            out_idx<=0; state<=OUT;
                        end else begin
                            iter<=iter+1'b1; layer<=0; group<=0; edge_idx<=0; bad_checks<=0;
                            for(l=0;l<9;l=l+1) synd_acc[l]<=0;
                            state<=QPASS;
                        end
                    end else begin
                        group<=group+1'b1;
                        edge_idx<=0;
                        bad_checks<=bad_checks | group_bad_c;
                        for(l=0;l<9;l=l+1) synd_acc[l]<=0;
                    end
                end else edge_idx<=edge_idx+1'b1;
            end
            OUT: if (out_ready) begin
                if (out_idx==10'd323) begin done<=1; state<=IDLE; end
                else out_idx<=out_idx+1'b1;
            end
            default: state<=IDLE;
            endcase
        end
    end
endmodule
/* verilator lint_on UNUSED */
/* verilator lint_on WIDTH */
