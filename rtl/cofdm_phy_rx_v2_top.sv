`timescale 1ns/1ps
// ADC-to-pre-LDPC reference integration, 122.88 MHz / 15.36 Msps.
// Raw IQ ring permits two passes through the SAME XFFT: coarse-corrected
// LTFs estimate residual CFO; replay LTFs/Header/data with total CFO. NCO
// phase advances on accepted samples (including CP), never during stalls.
// Midambles currently advance pilot PRBS but do not update H (static-H baseline).
module cofdm_phy_rx_v2_top #(
    parameter integer BUFFER_DEPTH=8192,
    parameter integer STF_TO_LTF_USEFUL=144,
    parameter integer PEAK_TO_BUFFER_OFFSET=0
)(
    input wire clk,rst,sample_valid,
    input wire signed [15:0] sample_re,sample_im,
    input wire [23:0] inv_noise_q16,
    input wire payload_ready,
    output wire payload_valid,payload_last,payload_cw_first,payload_cw_last,
    output wire signed [15:0] payload_llr,
    output wire header_valid,header_ok,crc_ok,
    output wire [11:0] payload_bytes,
    output wire [6:0] scrambler_seed,
    output wire [1:0] midamble_code,
    output wire header_error,header_busy,
    output wire frame_valid,capture_locked,capture_timeout,
    output wire [31:0] false_alarm_count,
    output wire replay_busy,replay_done,replay_error,fft_overflow,
    output reg frame_done,frame_error,
    output wire [4:0] state_dbg,
    output wire fine_valid,output wire signed [31:0] fine_phase_inc
);
    localparam [4:0] IDLE=0,START=1,FFT_WAIT=2,FINE_WAIT=3,
       CHANNEL_WAIT=4,HEADER_WAIT=5,LAYOUT=6,SYMBOL_WAIT=7,DRAIN=8,FAIL=9;
    localparam [255:0] ACTIVE={{100{1'b1}},{55{1'b0}},{100{1'b1}},1'b0};
    reg [4:0] state;
    assign state_dbg=state;
    reg [2:0] kind;
    reg fine_pass;
    reg [31:0] first_cp,cp_index;
    reg signed [31:0] replay_inc,coarse_snapshot;
    reg frame_reset,nco_clear,replay_start;
    reg [1:0] frame_reset_count;
    reg [15:0] data_remaining,data_bits_work;
    reg [4:0] period,data_since_mid;
    reg [15:0] cw_delivered;
    reg [19:0] watchdog;
    wire sync_start,peak_valid;
    wire [31:0] peak_index;
    wire signed [31:0] coarse_inc;
    cofdm_sync_ltf_cfo_top #(.ABSOLUTE_INDEX(1),.STF_TO_LTF_USEFUL(STF_TO_LTF_USEFUL),
      .CAP_LTF_MIN_OFFSET(16),.CAP_LTF_TIMEOUT(20000),.CAP_FINE_TIMEOUT(8192),
      .CAP_HEADER_TIMEOUT(8192)) sync_front(
      .clk,.rst,.sample_valid,.sample_re,.sample_im,.fine_valid,.fine_phase_inc,
      .header_crc_valid(header_valid),.header_crc_ok(header_ok),
      .frame_abort(frame_error),.frame_done,
      .fft_out_valid(1'b0),.fft_out_last(1'b0),.fft_out_re(16'sd0),.fft_out_im(16'sd0),
      .fft_rot_re(16'sd0),.fft_rot_im(16'sd0),.coarse_phase_inc(coarse_inc),
      .ltf_peak_valid(peak_valid),.ltf_peak_index(peak_index),.frame_start(sync_start),
      .frame_valid,.capture_locked,.capture_timeout,.false_alarm_count);

    wire rv,rr,rs; wire signed [15:0] rx,ry;
    cofdm_pre_fft_stream_replay #(.BUFFER_DEPTH(BUFFER_DEPTH)) replay(
      .clk,.rst,.sample_valid,.sample_re,.sample_im,.replay_start,
      .replay_start_index(cp_index),.replay_symbol_count(16'd1),.replay_extend_valid(1'b0),
      .out_valid(rv),.out_ready(rr),.out_re(rx),.out_im(ry),.out_symbol_start(rs),
      .out_symbol_index(),.replay_busy,.replay_done,.replay_error);
    // Credit counter covers NCO pipeline + 16-word FIFO. At most 8 samples
    // can be in flight, so no result is discarded when XFFT applies stalls.
    reg [4:0] credit;
    wire take=rv && rr;
    wire nv;wire signed [15:0] nx,ny;
    reg [2:0] start_pipe;
    wire qv,qr,qready;wire [32:0] qdata;
    assign rr=(credit<8) && qready && !frame_reset && state!=FAIL;
    always @(posedge clk) begin
      if(rst || frame_reset) begin credit<=0;start_pipe<=0; end
      else begin
        start_pipe<={start_pipe[1:0],take && rs};
        case({take,qv && qr})
          2'b10:credit<=credit+1'b1;
          2'b01:credit<=credit-1'b1;
          default:begin end
        endcase
      end
    end
    cofdm_cfo_nco_rotator nco(.clk,.rst(rst|frame_reset),.clear_phase(nco_clear),
      .sample_valid(take),.phase_inc(replay_inc),.in_re(rx),.in_im(ry),
      .out_valid(nv),.out_re(nx),.out_im(ny),.phase_dbg());
    cofdm_llr_fifo #(.WIDTH(33),.DEPTH(16)) nco_queue(
      .clk,.rst(rst|frame_reset),.in_valid(nv),.in_ready(qready),
      .in_data({start_pipe[2],ny,nx}),.out_valid(qv),.out_ready(qr),.out_data(qdata));
    wire fv,fr,fl;wire signed [15:0] fx,fy;wire [7:0] bin;
    cofdm_fft_stream_frontend xfft(.aclk(clk),.aresetn(!(rst|frame_reset)),
      .in_valid(qv),.in_ready(qr),.in_symbol_start(qdata[32]),
      .in_re(qdata[15:0]),.in_im(qdata[31:16]),.out_valid(fv),.out_ready(fr),
      .out_re(fx),.out_im(fy),.out_last(fl),.out_user(),.frame_started(),
      .fft_overflow,.input_halt(),.output_halt(),.config_done(),.accepted_fft_samples(),
      .out_bin_index(bin),.out_symbol_start(),.out_symbol_index(),.out_symbol_kind());
    wire fine_ready,fine_error;
    cofdm_ltf_fine_cfo_chain #(.ACTIVE_MASK(ACTIVE)) fine(
      .clk,.rst(rst|frame_reset),.fft_out_valid(fv && fine_pass),.fft_out_ready(fine_ready),
      .fft_out_last(fl),.fft_out_re(fx),.fft_out_im(fy),.rot_re(16'sd0),.rot_im(16'sd0),
      .phase_inc_valid(fine_valid),.phase_inc(fine_phase_inc),.frame_error(fine_error));
    wire freq_ready,channel_done,channel_error,noise_valid,freq_error,symbol_done;
    wire [15:0] n_codewords;
    wire [47:0] noise_variance;
    assign fr=fine_pass?fine_ready:freq_ready;
    cofdm_phy_rx_v2_freq_top freq(
      .clk,.rst,.frame_start(frame_reset),.inv_noise_q16,
      .fft_valid(fv && !fine_pass),.fft_ready(freq_ready),.fft_last(fl),.fft_bin(bin),
      .fft_symbol_kind(kind),.fft_re(fx),.fft_im(fy),
      .payload_valid,.payload_last,.payload_llr,.payload_ready,.payload_cw_first,.payload_cw_last,
      .header_valid,.header_ok,.crc_ok,.payload_bytes,.scrambler_seed,.midamble_code,
      .header_error,.header_busy,.channel_done,.channel_error,.noise_variance,.noise_valid,
      .n_codewords,.symbol_done,.frame_error(freq_error));
    wire fft_end=fv && fr && fl;
    always @(posedge clk) begin
      if(rst) begin
        state<=IDLE;kind<=0;fine_pass<=1;first_cp<=0;cp_index<=0;frame_reset_count<=3;
        replay_inc<=0;coarse_snapshot<=0;frame_reset<=0;nco_clear<=0;replay_start<=0;
        data_remaining<=0;data_bits_work<=0;period<=8;data_since_mid<=0;
        cw_delivered<=0;watchdog<=0;frame_done<=0;frame_error<=0;
      end else begin
        frame_reset<=0;nco_clear<=0;replay_start<=0;frame_done<=0;
        if (frame_reset_count != 0) begin
          frame_reset<=1; frame_reset_count<=frame_reset_count-1'b1;
        end
        if(state!=IDLE && state!=FAIL) watchdog<=watchdog+1'b1;else watchdog<=0;
        if(fft_end || symbol_done || header_valid) watchdog<=0;
        if(payload_valid && payload_ready && payload_cw_last) cw_delivered<=cw_delivered+1'b1;
        case(state)
          IDLE: if(sync_start) begin
            frame_reset<=1;frame_reset_count<=3;nco_clear<=1;frame_error<=0;fine_pass<=1;kind<=0;
            first_cp<=peak_index+32'(PEAK_TO_BUFFER_OFFSET-32);
            cp_index<=peak_index+32'(PEAK_TO_BUFFER_OFFSET-32);
            replay_inc<=coarse_inc;coarse_snapshot<=coarse_inc;cw_delivered<=0;
            data_since_mid<=0;state<=START;
          end
          START: begin replay_start<=1;state<=FFT_WAIT; end
          FFT_WAIT: if(fft_end) begin
            if(kind==0) begin kind<=1;cp_index<=cp_index+288;state<=START;end
            else if(kind==1) state<=fine_pass?FINE_WAIT:CHANNEL_WAIT;
            else if(kind==2) state<=HEADER_WAIT;
            else if(kind==3) state<=SYMBOL_WAIT;
            else begin kind<=3;cp_index<=cp_index+288;state<=START;end
          end
          FINE_WAIT: if(fine_valid) begin
            replay_inc<=coarse_snapshot+fine_phase_inc;fine_pass<=0;
            cp_index<=first_cp;kind<=0;nco_clear<=1;state<=START;
          end
          CHANNEL_WAIT: if(channel_done) begin
            kind<=2;cp_index<=cp_index+288;state<=START;
          end
          HEADER_WAIT: begin
            if(header_valid && !header_ok) begin frame_error<=1;state<=FAIL; end
            else if(n_codewords!=0) begin
              // n_codewords*648 fits 16 bits (max 33048); constant multiply.
              data_bits_work<=n_codewords*16'd648;data_remaining<=0;
              case(midamble_code) 0:period<=8;1:period<=4;default:period<=16;endcase
              state<=LAYOUT;
            end
          end
          LAYOUT: begin
            data_remaining<=data_remaining+1'b1;
            if(data_bits_work>384) data_bits_work<=data_bits_work-384;
            else begin kind<=3;cp_index<=cp_index+288;state<=START;end
          end
          SYMBOL_WAIT: if(symbol_done) begin
            data_remaining<=data_remaining-1'b1;
            if(data_remaining==1) state<=DRAIN;
            else begin
              cp_index<=cp_index+288;state<=START;
              if(data_since_mid+1==period) begin kind<=4;data_since_mid<=0;end
              else begin kind<=3;data_since_mid<=data_since_mid+1'b1;end
            end
          end
          DRAIN: if(cw_delivered==n_codewords) begin frame_done<=1;state<=IDLE;end
          FAIL: begin frame_reset<=1;state<=IDLE; end
          default:state<=IDLE;
        endcase
        if(state!=IDLE && state!=START && state!=FAIL &&
           (replay_error || fine_error || freq_error || header_error || fft_overflow || (&watchdog))) begin
          frame_error<=1;state<=FAIL;
        end
      end
    end
endmodule
