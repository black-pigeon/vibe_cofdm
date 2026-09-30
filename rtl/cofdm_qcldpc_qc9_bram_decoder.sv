`timescale 1ns/1ps
// BRAM-oriented QC9 decoder.  Nine processing elements cover one third of a
// Z=27 layer.  Unlike the arithmetic reference core, all large memories are
// synchronously read bank RAMs, so Vivado can map them to block RAM.
module cofdm_qcldpc_qc9_bram_decoder #(
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
    localparam [3:0] IDLE=0, LOAD=1, QPREP=2, QPREP2=3, QREAD=4, QACC=5, QMIN=6,
                     UWRITE_PREP=7, UWRITE=8, SPREP=9, SPREP2=10, SYNREAD=11, SYNACC=12,
                     OUTREAD=13, OUTWAIT=14, OUTHOLD=15;
    reg [3:0] state;
    reg [9:0] load_idx, out_idx;
    reg [3:0] layer;
    reg [1:0] group;
    reg [3:0] edge_idx;
    reg [4:0] iter;
    reg bad_checks;
    reg signed [8:0] q_cache [0:7][0:8];
    reg signed [8:0] q_reg [0:8];
    reg [8:0] q_mag_reg [0:8];
    reg q_sign_reg [0:8];
    reg [8:0] min1 [0:8], min2 [0:8];
    reg [3:0] min_edge [0:8];
    reg sign_acc [0:8], synd_acc [0:8];

    wire base_valid;
    wire [4:0] base_var_block, base_shift;
    wire [6:0] base_addr={layer,3'b000}+{3'b000,edge_idx};
    cofdm_qcldpc_qc_base_rom base_rom(.addr(base_addr),.valid(base_valid),
        .var_block(base_var_block),.shift(base_shift));

    integer l;
    wire [3:0] load_bank_i=4'(load_idx%10'd9);
    wire [6:0] load_addr_i=7'(load_idx/10'd9);
    wire [3:0] out_bank_i=4'(out_idx%10'd9);
    wire [6:0] out_addr_i=7'(out_idx/10'd9);
    wire [8:0] msg_addr_c=9'(layer)*9'd24+9'(group)*9'd8+9'(edge_idx);
    reg [3:0] var_bank_c [0:8];
    reg [3:0] map_bank_reg [0:8];
    reg [6:0] map_addr_reg [0:8];
    reg [8:0] map_msg_addr_reg [0:8];
    reg [3:0] map_pre_bank [0:8];
    reg [6:0] map_pre_addr [0:8];
    reg [8:0] map_pre_msg [0:8];
    reg [3:0] map_bank_table [0:7][0:8];
    reg [6:0] map_addr_table [0:7][0:8];
    reg [6:0] var_addr_c [0:8];
    reg [8:0] post_rd [0:8];
    reg [6:0] msg_rd [0:8];
    reg [8:0] post_out_rd [0:8];
    reg signed [8:0] q_c [0:8];
    reg [8:0] q_mag_c [0:8];
    reg q_sign_c [0:8];
    reg [8:0] selected_mag_c [0:8];
    reg [7:0] scale_full_c [0:8];
    reg [5:0] scaled_mag_c [0:8];
    reg signed [6:0] rnew_c [0:8];
    reg signed [8:0] post_new_c [0:8];
    reg hard_c [0:8];
    reg group_bad_c;

    reg [8:0] post_wr_en;
    reg [8:0] post_rd_en;
    reg [8:0] msg_wr_en;
    reg [8:0] msg_rd_en;
    reg [6:0] post_wr_addr [0:8];
    reg [6:0] post_rd_addr_reg [0:8];
    reg [8:0] post_wr_data [0:8];
    reg [8:0] msg_wr_addr [0:8], msg_rd_addr [0:8];
    reg [8:0] msg_rd_addr_reg [0:8];
    reg signed [6:0] msg_wr_data [0:8];
    reg signed [8:0] write_post_reg [0:8];
    reg signed [6:0] write_msg_reg [0:8];
    reg [6:0] post_rd_addr_ram [0:8];

    function automatic signed [8:0] sat9(input signed [10:0] x);
        begin
            if (x>11'sd255) sat9=9'sd255;
            else if (x< -11'sd255) sat9=-9'sd255;
            else sat9=x[8:0];
        end
    endfunction
    function automatic [7:0] scale_min(input [8:0] x);
        begin scale_min=8'((({2'b0,x}<<1)+{2'b0,x}+11'd2)>>2); end
    endfunction

    // Address generation and arithmetic are deliberately separated from RAM
    // enable generation.  Keeping the arithmetic in its own combinational
    // process avoids a false combinational feedback path through write data
    // (and lets Vivado infer the synchronous RAMs as block RAM).
    // Each fixed lane maps a 5-bit shift to a bank and a group carry.
    // Constant / and % below operate on six unsigned bits, never integers.
    genvar lane;
    generate for(lane=0;lane<9;lane=lane+1) begin : MAP
        wire [5:0] sum={1'b0,base_shift}+6'(lane);
        wire [3:0] bank=4'(sum%6'd9);
        wire [2:0] quotient=3'(sum/6'd9);
        wire [2:0] grp={1'b0,group}+quotient;
        wire [2:0] wrapped=(grp>=3'd3)?grp-3'd3:grp;
        always @* begin
            var_bank_c[lane]=bank;
            var_addr_c[lane]=7'(base_var_block)*7'd3+7'(wrapped);
        end
    end endgenerate
    always @* begin
        for(l=0;l<9;l=l+1) begin
            post_wr_addr[l]=0;
            msg_rd_addr[l]=0; msg_wr_addr[l]=0;
        end
        if (state==LOAD && in_valid) post_wr_addr[load_bank_i]=load_addr_i[6:0];
        if(state==QPREP || state==SPREP)
            for(l=0;l<9;l=l+1) msg_rd_addr[l]=msg_addr_c;
        // RAM request cycles use the registered map.  This cuts the ROM and
        // QC address arithmetic out of the RAM address setup path.
        if (state==QREAD || state==SYNREAD) begin
            for(l=0;l<9;l=l+1) begin
                post_wr_addr[map_bank_reg[l]]=map_addr_reg[l];
                msg_rd_addr[l]=map_msg_addr_reg[l];
                msg_wr_addr[l]=map_msg_addr_reg[l];
            end
        end
        if (state==UWRITE) begin
            for(l=0;l<9;l=l+1) begin
                post_wr_addr[map_bank_table[edge_idx[2:0]][l]]=map_addr_table[edge_idx[2:0]][l];
                msg_wr_addr[l]=msg_addr_c;
            end
        end
        // The normal decoder read address is registered in QPREP/SPREP.  The
        // output drain is a separate, low-rate read and selects the requested
        // bank for one cycle through this mux.
        for(l=0;l<9;l=l+1) post_rd_addr_ram[l]=post_rd_addr_reg[l];
        if(state==OUTREAD) post_rd_addr_ram[out_bank_i]=out_addr_i[6:0];
        for(l=0;l<9;l=l+1) begin
            // QACC/SYNACC consume the registered map for the preceding read;
            // using it here avoids a large edge-indexed mux in the arithmetic
            // critical path.
            q_c[l]=sat9($signed({post_rd[map_bank_reg[l]][8],post_rd[map_bank_reg[l]]})-
                ((iter==0)?11'sd0:$signed({{4{msg_rd[l][6]}},msg_rd[l]})));
            q_mag_c[l]=q_c[l][8]?$unsigned(-q_c[l]):$unsigned(q_c[l]);
            q_sign_c[l]=q_c[l][8];
            selected_mag_c[l]=(min_edge[l]==edge_idx)?min2[l]:min1[l];
            scale_full_c[l]=scale_min(selected_mag_c[l]);
            scaled_mag_c[l]=(scale_full_c[l]>8'd63)?6'd63:scale_full_c[l][5:0];
            rnew_c[l]=(sign_acc[l]^q_cache[edge_idx[2:0]][l][8])?
                -$signed({1'b0,scaled_mag_c[l]}):$signed({1'b0,scaled_mag_c[l]});
            post_new_c[l]=sat9($signed({q_cache[edge_idx[2:0]][l][8],q_cache[edge_idx[2:0]][l]})+
                $signed({{4{rnew_c[l][6]}},rnew_c[l]}));
            hard_c[l]=post_rd[map_bank_reg[l]][8];
        end
        group_bad_c=1'b0;
        for(l=0;l<9;l=l+1)
            if(state==SYNACC) group_bad_c=group_bad_c | (synd_acc[l] ^ (base_valid?hard_c[l]:1'b0));
    end

    // RAM controls are generated from the already-computed arithmetic.  The
    // separate process is important: post_new_c/rnew_c are never read before
    // they are assigned, so lint and synthesis do not see a combinational loop.
    always @* begin
        post_wr_en='0; post_rd_en='0; msg_wr_en='0; msg_rd_en='0;
        for(l=0;l<9;l=l+1) begin
            post_wr_data[l]=0; msg_wr_data[l]=0;
        end
        if (state==LOAD && in_valid) begin
            post_wr_en[load_bank_i]=1'b1;
            post_wr_data[load_bank_i]=(in_llr==-7'sd64)?-9'sd63:$signed({{2{in_llr[6]}},in_llr});
        end
        if (state==QREAD && base_valid) begin
            for(l=0;l<9;l=l+1) begin
                post_rd_en[map_bank_reg[l]]=1'b1;
                msg_rd_en[l]=1'b1;
            end
        end
        if (state==SYNREAD && base_valid) begin
            for(l=0;l<9;l=l+1) post_rd_en[map_bank_reg[l]]=1'b1;
        end
        if (state==UWRITE && base_valid) begin
            for(l=0;l<9;l=l+1) begin
                post_wr_en[map_bank_table[edge_idx[2:0]][l]]=1'b1;
                post_wr_data[map_bank_table[edge_idx[2:0]][l]]=write_post_reg[l];
                msg_wr_en[l]=1'b1;
                msg_wr_data[l]=write_msg_reg[l];
            end
        end
        if (state==OUTREAD) post_rd_en[out_bank_i]=1'b1;
    end

    genvar g;
    generate for(g=0;g<9;g=g+1) begin : POST_BANK
        cofdm_qcldpc_sync_ram #(.DEPTH(72),.DATA_W(9),.ADDR_W(7)) post_ram(
            .clk,.rst,.wr_en(post_wr_en[g]),.wr_addr(post_wr_addr[g]),.wr_data(post_wr_data[g]),
            .rd_en(post_rd_en[g]),.rd_addr(post_rd_addr_ram[g]),.rd_data(post_rd[g]));
    end endgenerate
    generate for(g=0;g<9;g=g+1) begin : MSG_BANK
        cofdm_qcldpc_sync_ram #(.DEPTH(288),.DATA_W(7),.ADDR_W(9)) msg_ram(
            .clk,.rst,.wr_en(msg_wr_en[g]),.wr_addr(msg_wr_addr[g]),.wr_data(msg_wr_data[g]),
            .rd_en(msg_rd_en[g]),.rd_addr(msg_rd_addr_reg[g]),.rd_data(msg_rd[g]));
    end endgenerate
    assign busy=(state!=IDLE); assign in_ready=(state==LOAD)&&!rst;
    assign out_valid=(state==OUTHOLD); assign out_last=(state==OUTHOLD)&&(out_idx==10'd323);
    // OUTREAD clocks the selected bank; during the following OUTHOLD cycle
    // post_rd already contains that bank's registered value.
    assign out_bit=(state==OUTHOLD)?post_out_rd[out_idx%9][8]:1'b0;
    initial if(MAX_ITERS<1 || MAX_ITERS>31) $error("MAX_ITERS must be 1..31");

    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE; load_idx<=0; out_idx<=0; layer<=0; group<=0; edge_idx<=0; iter<=0;
            bad_checks<=0; done<=0; decode_ok<=0; syndrome_ok<=0; iterations_done<=0; frame_error<=0;
            for(l=0;l<9;l=l+1) begin
                min1[l]<=511;min2[l]<=511;min_edge[l]<=0;sign_acc[l]<=0;synd_acc[l]<=0;post_out_rd[l]<=0;
                q_reg[l]<=0;q_mag_reg[l]<=0;q_sign_reg[l]<=0;map_bank_reg[l]<=0;map_addr_reg[l]<=0;map_msg_addr_reg[l]<=0;
                write_post_reg[l]<=0;write_msg_reg[l]<=0;
                post_rd_addr_reg[l]<=0;msg_rd_addr_reg[l]<=0;
                map_bank_table[0][l]<=0;map_addr_table[0][l]<=0;
                map_bank_table[1][l]<=0;map_addr_table[1][l]<=0;
                map_bank_table[2][l]<=0;map_addr_table[2][l]<=0;
                map_bank_table[3][l]<=0;map_addr_table[3][l]<=0;
                map_bank_table[4][l]<=0;map_addr_table[4][l]<=0;
                map_bank_table[5][l]<=0;map_addr_table[5][l]<=0;
                map_bank_table[6][l]<=0;map_addr_table[6][l]<=0;
                map_bank_table[7][l]<=0;map_addr_table[7][l]<=0;
            end
        end else begin
            done<=0; frame_error<=0;
            case(state)
            IDLE: if(start) begin state<=LOAD;load_idx<=0;decode_ok<=0;syndrome_ok<=0;iterations_done<=0;end
            LOAD: if(in_valid) begin
                if(in_last!=(load_idx==647)) begin frame_error<=1;state<=IDLE;end
                else if(load_idx==647) begin
                    layer<=0;group<=0;edge_idx<=0;iter<=0;bad_checks<=0;
                    for(l=0;l<9;l=l+1) begin min1[l]<=511;min2[l]<=511;min_edge[l]<=0;sign_acc[l]<=0;end
                    state<=QPREP;
                end else load_idx<=load_idx+1'b1;
            end
            QPREP: begin
                if(base_valid) for(l=0;l<9;l=l+1) begin
                    map_pre_bank[l]<=var_bank_c[l];
                    map_pre_addr[l]<=var_addr_c[l];
                    map_pre_msg[l]<=msg_rd_addr[l];
                end
                state<=QPREP2;
            end
            QPREP2: begin
                if(base_valid) for(l=0;l<9;l=l+1) begin
                    map_bank_reg[l]<=map_pre_bank[l];
                    map_addr_reg[l]<=map_pre_addr[l];
                    map_msg_addr_reg[l]<=map_pre_msg[l];
                    post_rd_addr_reg[map_pre_bank[l]]<=map_pre_addr[l];
                    msg_rd_addr_reg[l]<=map_pre_msg[l];
                    map_bank_table[edge_idx[2:0]][l]<=map_pre_bank[l];
                    map_addr_table[edge_idx[2:0]][l]<=map_pre_addr[l];
                end
                state<=QREAD;
            end
            QREAD: state<=QACC;
            QACC: begin
                // Separate the RAM-to-arithmetic stage from the min-search
                // stage.  This costs one cycle per edge but removes the
                // posterior RAM -> subtraction -> compare path from the
                // 122.88 MHz timing budget.
                if(base_valid) for(l=0;l<9;l=l+1) begin
                    q_reg[l]<=q_c[l]; q_mag_reg[l]<=q_mag_c[l]; q_sign_reg[l]<=q_sign_c[l];
                end
                state<=QMIN;
            end
            QMIN: begin
                if(base_valid) for(l=0;l<9;l=l+1) begin
                    q_cache[edge_idx[2:0]][l]<=q_reg[l]; sign_acc[l]<=sign_acc[l]^q_sign_reg[l];
                    if(q_mag_reg[l]<min1[l]) begin min2[l]<=min1[l];min1[l]<=q_mag_reg[l];min_edge[l]<=edge_idx;end
                    else if(q_mag_reg[l]<min2[l]) min2[l]<=q_mag_reg[l];
                end
                if(edge_idx==7) begin edge_idx<=0;state<=UWRITE_PREP;end else begin edge_idx<=edge_idx+1'b1;state<=QPREP;end
            end
            UWRITE_PREP: begin
                for(l=0;l<9;l=l+1) begin
                    write_post_reg[l]<=post_new_c[l];
                    write_msg_reg[l]<=rnew_c[l];
                end
                state<=UWRITE;
            end
            UWRITE: begin
                if(edge_idx==7) begin
                    for(l=0;l<9;l=l+1) begin min1[l]<=511;min2[l]<=511;min_edge[l]<=0;sign_acc[l]<=0;end
                    if(group==2) begin group<=0;
                        if(layer==11) begin layer<=0;edge_idx<=0;bad_checks<=0;for(l=0;l<9;l=l+1) synd_acc[l]<=0;state<=SPREP;end
                        else begin layer<=layer+1'b1;edge_idx<=0;state<=QPREP;end
                    end else begin group<=group+1'b1;edge_idx<=0;state<=QPREP;end
                end else begin edge_idx<=edge_idx+1'b1;state<=UWRITE_PREP;end
            end
            SPREP: begin
                if(base_valid) for(l=0;l<9;l=l+1) begin
                    map_pre_bank[l]<=var_bank_c[l];
                    map_pre_addr[l]<=var_addr_c[l];
                    map_pre_msg[l]<=msg_rd_addr[l];
                end
                state<=SPREP2;
            end
            SPREP2: begin
                if(base_valid) for(l=0;l<9;l=l+1) begin
                    map_bank_reg[l]<=map_pre_bank[l];
                    map_addr_reg[l]<=map_pre_addr[l];
                    map_msg_addr_reg[l]<=map_pre_msg[l];
                    post_rd_addr_reg[map_pre_bank[l]]<=map_pre_addr[l];
                    msg_rd_addr_reg[l]<=map_pre_msg[l];
                end
                state<=SYNREAD;
            end
            SYNREAD: state<=SYNACC;
            SYNACC: begin
                if(base_valid) for(l=0;l<9;l=l+1) synd_acc[l]<=synd_acc[l]^hard_c[l];
                if(edge_idx==7) begin
                    if(group==2 && layer==11) begin
                        bad_checks<=bad_checks|group_bad_c;iterations_done<=iter+1'b1;
                        if(!(bad_checks|group_bad_c)||iter==5'(MAX_ITERS-1)) begin
                            decode_ok<=!(bad_checks|group_bad_c);syndrome_ok<=!(bad_checks|group_bad_c);out_idx<=0;state<=OUTREAD;
                        end else begin
                            iter<=iter+1'b1;layer<=0;group<=0;edge_idx<=0;bad_checks<=0;for(l=0;l<9;l=l+1) synd_acc[l]<=0;state<=QPREP;
                        end
                    end else begin
                        if(group==2) begin group<=0;layer<=layer+1'b1;end
                        else group<=group+1'b1;
                        edge_idx<=0;bad_checks<=bad_checks|group_bad_c;for(l=0;l<9;l=l+1) synd_acc[l]<=0;state<=SPREP;end
                end else begin edge_idx<=edge_idx+1'b1;state<=SPREP;end
            end
            OUTREAD: state<=OUTWAIT;
            OUTWAIT: begin
                post_out_rd[out_idx%9]<=post_rd[out_idx%9];
                state<=OUTHOLD;
            end
            OUTHOLD: if(out_ready) begin if(out_idx==323) begin done<=1;state<=IDLE;end else begin out_idx<=out_idx+1'b1;state<=OUTREAD;end end
            default: state<=IDLE;
            endcase
        end
    end
endmodule
