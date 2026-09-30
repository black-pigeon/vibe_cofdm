#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTL="$ROOT/rtl"
cd "$ROOT/.."
python3 "$ROOT/tests/verify_ltf_coe.py"
python3 "$ROOT/tests/verify_ltf_freq_rom.py"
python3 "$ROOT/tests/verify_ltf_rot_rom.py"
iverilog -g2012 -o /tmp/cofdm_fusion_tb "$RTL/cofdm_fusion_lane.sv" "$RTL/tb/tb_fusion_kernel.sv"
vvp /tmp/cofdm_fusion_tb
iverilog -g2012 -o /tmp/cofdm_quad_tb "$RTL/cofdm_quadrant_select.sv" "$RTL/tb/tb_quadrant.sv"
vvp /tmp/cofdm_quad_tb
iverilog -g2012 -o /tmp/cofdm_mid_tb "$RTL/cofdm_mid_fusion_ctrl.sv" "$RTL/tb/tb_mid_fusion_ctrl.sv"
vvp /tmp/cofdm_mid_tb
verilator --lint-only -Wall --top-module cofdm_quadrant_select "$RTL/cofdm_quadrant_select.sv"
verilator --lint-only -Wall --top-module cofdm_fusion_lane "$RTL/cofdm_fusion_lane.sv"
verilator --lint-only -Wall --top-module cofdm_mid_fusion_ctrl "$RTL/cofdm_mid_fusion_ctrl.sv"
iverilog -g2012 -o /tmp/cofdm_stf_tb "$RTL/cofdm_stf_sync_frontend.sv" "$RTL/tb/tb_stf_sync_frontend.sv"
vvp /tmp/cofdm_stf_tb
verilator --lint-only -Wall --top-module cofdm_stf_sync_frontend "$RTL/cofdm_stf_sync_frontend.sv"
iverilog -g2012 -o /tmp/cofdm_nco_tb "$RTL/cofdm_cfo_nco_rotator.sv" "$RTL/tb/tb_cfo_nco_rotator.sv"
vvp /tmp/cofdm_nco_tb
verilator --lint-only -Wall --top-module cofdm_cfo_nco_rotator "$RTL/cofdm_cfo_nco_rotator.sv"
iverilog -g2012 -o /tmp/cofdm_angle_tb "$RTL/cofdm_cfo_angle_estimator.sv" "$RTL/tb/tb_cfo_angle_estimator.sv"
vvp /tmp/cofdm_angle_tb
verilator --lint-only -Wall --top-module cofdm_cfo_angle_estimator "$RTL/cofdm_cfo_angle_estimator.sv"
iverilog -g2012 -o /tmp/cofdm_capture_tb "$RTL/cofdm_capture_ctrl.sv" "$RTL/tb/tb_capture_ctrl.sv"
vvp /tmp/cofdm_capture_tb
verilator --lint-only -Wall --top-module cofdm_capture_ctrl "$RTL/cofdm_capture_ctrl.sv"
iverilog -g2012 -o /tmp/cofdm_ltf_accum_tb "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_fine_cfo_accum.sv" "$RTL/tb/tb_ltf_fine_cfo_accum.sv"
vvp /tmp/cofdm_ltf_accum_tb
verilator --lint-only -Wall --top-module cofdm_ltf_fine_cfo_accum \
  "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_fine_cfo_accum.sv"
iverilog -g2012 -o /tmp/cofdm_cordic_tb "$RTL/cofdm_cordic_atan2.sv" "$RTL/tb/tb_cordic_atan2.sv"
vvp /tmp/cofdm_cordic_tb
verilator --lint-only -Wall --top-module cofdm_cordic_atan2 "$RTL/cofdm_cordic_atan2.sv"
iverilog -g2012 -o /tmp/cofdm_phase_inc_tb "$RTL/cofdm_fine_cfo_phase_to_inc.sv" "$RTL/tb/tb_fine_cfo_phase_to_inc.sv"
vvp /tmp/cofdm_phase_inc_tb
verilator --lint-only -Wall --top-module cofdm_fine_cfo_phase_to_inc "$RTL/cofdm_fine_cfo_phase_to_inc.sv"
iverilog -g2012 -o /tmp/cofdm_ltf_adapter_tb "$RTL/cofdm_ltf_fft_stream_adapter.sv" "$RTL/tb/tb_ltf_fft_stream_adapter.sv"
vvp /tmp/cofdm_ltf_adapter_tb
verilator --lint-only -Wall --top-module cofdm_ltf_fft_stream_adapter "$RTL/cofdm_ltf_fft_stream_adapter.sv"
iverilog -g2012 -o /tmp/cofdm_ltf_chain_tb \
  "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_fine_cfo_accum.sv" "$RTL/cofdm_ltf_fft_stream_adapter.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_fine_cfo_phase_to_inc.sv" \
  "$RTL/cofdm_ltf_fine_cfo_chain.sv" "$RTL/tb/tb_ltf_fine_cfo_chain.sv"
vvp /tmp/cofdm_ltf_chain_tb
iverilog -g2012 -s tb_ltf_fine_cfo_chain_zc -o /tmp/cofdm_ltf_chain_zc_tb \
  "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_freq_rom.sv" \
  "$RTL/cofdm_ltf_fine_cfo_accum.sv" "$RTL/cofdm_ltf_fft_stream_adapter.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_fine_cfo_phase_to_inc.sv" \
  "$RTL/cofdm_ltf_fine_cfo_chain.sv" "$RTL/tb/tb_ltf_fine_cfo_chain_zc.sv"
vvp /tmp/cofdm_ltf_chain_zc_tb
verilator --lint-only -Wall --top-module cofdm_ltf_fine_cfo_chain \
  "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_fine_cfo_accum.sv" "$RTL/cofdm_ltf_fft_stream_adapter.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_fine_cfo_phase_to_inc.sv" \
  "$RTL/cofdm_ltf_fine_cfo_chain.sv"
iverilog -g2012 -o /tmp/cofdm_ltf_match_tb "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_time_matcher.sv" "$RTL/tb/tb_ltf_time_matcher.sv"
vvp /tmp/cofdm_ltf_match_tb
verilator --lint-only -Wall --top-module cofdm_ltf_time_matcher "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_time_matcher.sv"
iverilog -g2012 -o /tmp/cofdm_ltf_match_tdm_tb "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_sample_buffer.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv" "$RTL/tb/tb_ltf_time_matcher_tdm.sv"
vvp /tmp/cofdm_ltf_match_tdm_tb
verilator --lint-only -Wall --top-module cofdm_ltf_time_matcher_tdm "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_sample_buffer.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv"
iverilog -g2012 -o /tmp/cofdm_nco_ltf_bridge_tb \
  "$RTL/cofdm_cfo_nco_rotator.sv" "$RTL/cofdm_ltf_template_rom.sv" \
  "$RTL/cofdm_ltf_sample_buffer.sv" "$RTL/cofdm_ltf_time_matcher.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv" \
  "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/cofdm_ltf_sync_capture_frontend.sv" \
  "$RTL/cofdm_nco_ltf_sync_bridge.sv" "$RTL/tb/tb_nco_ltf_sync_bridge.sv"
vvp /tmp/cofdm_nco_ltf_bridge_tb
verilator --lint-only -Wall --top-module cofdm_nco_ltf_sync_bridge \
  "$RTL/cofdm_cfo_nco_rotator.sv" "$RTL/cofdm_ltf_template_rom.sv" \
  "$RTL/cofdm_ltf_sample_buffer.sv" "$RTL/cofdm_ltf_time_matcher.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv" \
  "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/cofdm_ltf_sync_capture_frontend.sv" \
  "$RTL/cofdm_nco_ltf_sync_bridge.sv"
verilator --lint-only -Wall -Wno-UNUSED -Wno-PINCONNECTEMPTY --top-module cofdm_sync_ltf_cfo_top \
  "$RTL/cofdm_stf_sync_frontend.sv" "$RTL/cofdm_cfo_angle_estimator.sv" \
  "$RTL/cofdm_cfo_control.sv" "$RTL/cofdm_cfo_nco_rotator.sv" \
  "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_sample_buffer.sv" \
  "$RTL/cofdm_ltf_time_matcher.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv" \
  "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/cofdm_ltf_sync_capture_frontend.sv" \
  "$RTL/cofdm_nco_ltf_sync_bridge.sv" "$RTL/cofdm_capture_ctrl.sv" \
  "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_fine_cfo_accum.sv" "$RTL/cofdm_ltf_fft_stream_adapter.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_fine_cfo_phase_to_inc.sv" \
  "$RTL/cofdm_ltf_fine_cfo_chain.sv" \
  "$RTL/cofdm_sync_ltf_cfo_top.sv"
iverilog -g2012 -s tb_sync_ltf_cfo_top -o /tmp/cofdm_sync_ltf_cfo_top_tb \
  "$RTL/cofdm_stf_sync_frontend.sv" "$RTL/cofdm_cfo_angle_estimator.sv" \
  "$RTL/cofdm_cfo_control.sv" "$RTL/cofdm_cfo_nco_rotator.sv" \
  "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_sample_buffer.sv" \
  "$RTL/cofdm_ltf_time_matcher.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv" \
  "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/cofdm_ltf_sync_capture_frontend.sv" \
  "$RTL/cofdm_nco_ltf_sync_bridge.sv" "$RTL/cofdm_capture_ctrl.sv" \
  "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_fine_cfo_accum.sv" "$RTL/cofdm_ltf_fft_stream_adapter.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_fine_cfo_phase_to_inc.sv" \
  "$RTL/cofdm_ltf_fine_cfo_chain.sv" \
  "$RTL/cofdm_sync_ltf_cfo_top.sv" "$RTL/tb/tb_sync_ltf_cfo_top.sv"
vvp /tmp/cofdm_sync_ltf_cfo_top_tb
iverilog -g2012 -s tb_pre_fft_replay -o /tmp/cofdm_pre_fft_replay_tb \
  "$RTL/cofdm_pre_fft_replay_mem.sv" "$RTL/cofdm_pre_fft_replay.sv" "$RTL/tb/tb_pre_fft_replay.sv"
vvp /tmp/cofdm_pre_fft_replay_tb
iverilog -g2012 -s tb_pre_fft_stream_replay -o /tmp/cofdm_pre_fft_stream_replay_tb \
  "$RTL/cofdm_pre_fft_replay_mem.sv" "$RTL/cofdm_pre_fft_stream_replay.sv" \
  "$RTL/tb/tb_pre_fft_stream_replay.sv"
vvp /tmp/cofdm_pre_fft_stream_replay_tb
iverilog -g2012 -s tb_replay_stalls -o /tmp/cofdm_replay_stalls_tb \
  "$RTL/cofdm_pre_fft_replay_mem.sv" "$RTL/cofdm_pre_fft_stream_replay.sv" \
  "$RTL/tb/tb_replay_stalls.sv"
vvp /tmp/cofdm_replay_stalls_tb
iverilog -g2012 -s tb_capture_sparse_events -o /tmp/cofdm_capture_sparse_tb \
  "$RTL/cofdm_capture_ctrl.sv" "$RTL/tb/tb_capture_sparse_events.sv"
vvp /tmp/cofdm_capture_sparse_tb
iverilog -g2012 -s tb_ltf_channel_estimator -o /tmp/cofdm_ltf_channel_tb \
  "$RTL/cofdm_ltf_freq_rom.sv" "$RTL/cofdm_ltf_channel_estimator.sv" \
  "$RTL/tb/tb_ltf_channel_estimator.sv"
vvp /tmp/cofdm_ltf_channel_tb
iverilog -g2012 -s tb_ltf_channel_estimator_sparse -o /tmp/cofdm_ltf_channel_sparse_tb \
  "$RTL/cofdm_ltf_freq_rom.sv" "$RTL/cofdm_ltf_channel_estimator.sv" \
  "$RTL/tb/tb_ltf_channel_estimator_sparse.sv"
vvp /tmp/cofdm_ltf_channel_sparse_tb
iverilog -g2012 -s tb_pilot_llr -o /tmp/cofdm_pilot_llr_tb \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_pilot_phase_accum.sv" \
  "$RTL/cofdm_matched_llr.sv" "$RTL/tb/tb_pilot_llr.sv"
vvp /tmp/cofdm_pilot_llr_tb
iverilog -g2012 -s tb_common_phase_rotator -o /tmp/cofdm_phase_rot_tb \
  "$RTL/cofdm_phase_lut.sv" "$RTL/cofdm_common_phase_rotator.sv" \
  "$RTL/tb/tb_common_phase_rotator.sv"
vvp /tmp/cofdm_phase_rot_tb
iverilog -g2012 -s tb_pre_ldpc_symbol -o /tmp/cofdm_pre_ldpc_tb \
  "$RTL/cofdm_phase_lut.sv" "$RTL/cofdm_common_phase_rotator.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_pilot_phase_accum.sv" \
  "$RTL/cofdm_matched_llr.sv" "$RTL/cofdm_pre_ldpc_symbol.sv" \
  "$RTL/tb/tb_pre_ldpc_symbol.sv"
vvp /tmp/cofdm_pre_ldpc_tb
iverilog -g2012 -s tb_pilot_prbs -o /tmp/cofdm_pilot_prbs_tb \
  "$RTL/cofdm_pilot_prbs.sv" "$RTL/cofdm_symbol_pilots.sv" "$RTL/tb/tb_pilot_prbs.sv"
vvp /tmp/cofdm_pilot_prbs_tb
iverilog -g2012 -s tb_header_descrambler -o /tmp/cofdm_header_descrambler_tb \
  "$RTL/cofdm_header_descrambler.sv" "$RTL/tb/tb_header_descrambler.sv"
vvp /tmp/cofdm_header_descrambler_tb
iverilog -g2012 -s tb_llr_deinterleaver -o /tmp/cofdm_llr_deinterleaver_tb \
  "$RTL/cofdm_llr_deinterleaver.sv" "$RTL/tb/tb_llr_deinterleaver.sv"
vvp /tmp/cofdm_llr_deinterleaver_tb
iverilog -g2012 -s tb_llr_packetizer -o /tmp/cofdm_packetizer_tb \
  "$RTL/cofdm_llr_packetizer.sv" "$RTL/tb/tb_llr_packetizer.sv"
vvp /tmp/cofdm_packetizer_tb
iverilog -g2012 -s tb_qcldpc_648_decoder -o /tmp/cofdm_qcldpc_tb \
  "$RTL/cofdm_qcldpc_edge_rom.sv" "$RTL/cofdm_qcldpc_648_decoder.sv" "$RTL/tb/tb_qcldpc_648_decoder.sv"
vvp /tmp/cofdm_qcldpc_tb
iverilog -g2012 -s tb_qcldpc_codeword_scheduler -o /tmp/cofdm_qcldpc_scheduler_tb \
  "$RTL/cofdm_qcldpc_edge_rom.sv" "$RTL/cofdm_qcldpc_648_decoder.sv" \
  "$RTL/cofdm_qcldpc_bram_replica.sv" \
  "$RTL/cofdm_qcldpc_parallel_bank.sv" "$RTL/cofdm_qcldpc_codeword_scheduler.sv" \
  "$RTL/tb/tb_qcldpc_codeword_scheduler.sv"
vvp /tmp/cofdm_qcldpc_scheduler_tb
iverilog -g2012 -s tb_qcldpc_qc9_decoder -o /tmp/cofdm_qcldpc_qc9_tb \
  "$RTL/cofdm_qcldpc_qc_base_rom.sv" "$RTL/cofdm_qcldpc_qc9_decoder.sv" \
  "$RTL/tb/tb_qcldpc_qc9_decoder.sv"
vvp /tmp/cofdm_qcldpc_qc9_tb
iverilog -g2012 -s tb_qcldpc_qc9_bram_decoder -o /tmp/cofdm_qcldpc_qc9_bram_tb \
  "$RTL/cofdm_qcldpc_qc_base_rom.sv" "$RTL/cofdm_qcldpc_sync_ram.sv" \
  "$RTL/cofdm_qcldpc_qc9_bram_decoder.sv" "$RTL/tb/tb_qcldpc_qc9_bram_decoder.sv"
vvp /tmp/cofdm_qcldpc_qc9_bram_tb
iverilog -g2012 -s tb_qcldpc_648_vector -o /tmp/cofdm_qcldpc_vec_tb \
  "$RTL/cofdm_qcldpc_edge_rom.sv" "$RTL/cofdm_qcldpc_648_decoder.sv" "$RTL/tb/tb_qcldpc_648_vector.sv"
vvp /tmp/cofdm_qcldpc_vec_tb
iverilog -g2012 -s tb_payload_codeword_bridge -o /tmp/cofdm_payload_bridge_tb \
  "$RTL/cofdm_qcldpc_edge_rom.sv" "$RTL/cofdm_qcldpc_648_decoder.sv" "$RTL/cofdm_payload_codeword_bridge.sv" \
  "$RTL/tb/tb_payload_codeword_bridge.sv"
vvp /tmp/cofdm_payload_bridge_tb
iverilog -g2012 -s tb_v2_header_decoder -o /tmp/cofdm_v2_header_tb \
  "$RTL/cofdm_v2_header_decoder.sv" "$RTL/tb/tb_v2_header_decoder.sv"
vvp /tmp/cofdm_v2_header_tb
iverilog -g2012 -s tb_v2_header_decoder_tdm -o /tmp/cofdm_v2_header_tdm_tb \
  "$RTL/cofdm_v2_header_decoder_tdm.sv" "$RTL/tb/tb_v2_header_decoder_tdm.sv"
vvp /tmp/cofdm_v2_header_tdm_tb
verilator --lint-only -Wall --top-module cofdm_v2_header_decoder_tdm \
  "$RTL/cofdm_v2_header_decoder_tdm.sv"
iverilog -g2012 -s tb_v2_header_frontend -o /tmp/cofdm_v2_header_frontend_tb \
  "$RTL/cofdm_v2_header_decoder.sv" "$RTL/cofdm_v2_header_frontend.sv" \
  "$RTL/tb/tb_v2_header_frontend.sv"
vvp /tmp/cofdm_v2_header_frontend_tb
iverilog -g2012 -s tb_v2_rx_header_path -o /tmp/cofdm_v2_rx_header_path_tb \
  "$RTL/cofdm_v2_header_decoder_tdm.sv" "$RTL/cofdm_v2_rx_header_path.sv" \
  "$RTL/tb/tb_v2_rx_header_path.sv"
vvp /tmp/cofdm_v2_rx_header_path_tb
verilator --lint-only -Wall --top-module cofdm_llr_packetizer "$RTL/cofdm_llr_packetizer.sv"
verilator --lint-only -Wall --top-module cofdm_v2_header_decoder "$RTL/cofdm_v2_header_decoder.sv"
verilator --lint-only -Wall --top-module cofdm_v2_header_frontend \
  "$RTL/cofdm_v2_header_decoder.sv" "$RTL/cofdm_v2_header_frontend.sv"
verilator --lint-only -Wall --top-module cofdm_v2_rx_header_path \
  "$RTL/cofdm_v2_header_decoder_tdm.sv" "$RTL/cofdm_v2_rx_header_path.sv"
verilator --lint-only -Wall -Wno-UNUSED -Wno-PINCONNECTEMPTY \
  --top-module cofdm_phy_rx_v2_freq_top \
  "$RTL/cofdm_phase_lut.sv" "$RTL/cofdm_common_phase_rotator.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_pilot_phase_accum.sv" \
  "$RTL/cofdm_matched_llr.sv" "$RTL/cofdm_pre_ldpc_symbol.sv" \
  "$RTL/cofdm_pilot_prbs.sv" "$RTL/cofdm_symbol_pilots.sv" \
  "$RTL/cofdm_header_descrambler.sv" "$RTL/cofdm_llr_packetizer.sv" \
  "$RTL/cofdm_llr_fifo.sv" "$RTL/cofdm_pre_ldpc_stream.sv" \
  "$RTL/cofdm_v2_header_decoder_tdm.sv" "$RTL/cofdm_v2_rx_header_path.sv" \
  "$RTL/cofdm_ltf_freq_rom.sv" "$RTL/cofdm_ltf_fft_stream_adapter.sv" \
  "$RTL/cofdm_ltf_channel_estimator.sv" "$RTL/cofdm_ltf_channel_chain.sv" \
  "$RTL/cofdm_phy_rx_v2_freq_top.sv"
verilator --lint-only -Wall --top-module cofdm_symbol_pilots "$RTL/cofdm_symbol_pilots.sv"
verilator --lint-only -Wall --top-module cofdm_pilot_prbs "$RTL/cofdm_pilot_prbs.sv"
verilator --lint-only -Wall --top-module cofdm_header_descrambler "$RTL/cofdm_header_descrambler.sv"
verilator --lint-only -Wall --top-module cofdm_llr_deinterleaver "$RTL/cofdm_llr_deinterleaver.sv"
verilator --lint-only -Wall --top-module cofdm_qcldpc_648_decoder \
  "$RTL/cofdm_qcldpc_edge_rom.sv" "$RTL/cofdm_qcldpc_648_decoder.sv"
verilator --lint-only -Wall --top-module cofdm_qcldpc_codeword_scheduler \
  "$RTL/cofdm_qcldpc_edge_rom.sv" "$RTL/cofdm_qcldpc_648_decoder.sv" \
  "$RTL/cofdm_qcldpc_bram_replica.sv" \
  "$RTL/cofdm_qcldpc_parallel_bank.sv" "$RTL/cofdm_qcldpc_codeword_scheduler.sv"
verilator --lint-only -Wall --top-module cofdm_qcldpc_qc9_decoder \
  "$RTL/cofdm_qcldpc_qc_base_rom.sv" "$RTL/cofdm_qcldpc_qc9_decoder.sv"
verilator --lint-only -Wall --top-module cofdm_qcldpc_qc9_bram_decoder \
  "$RTL/cofdm_qcldpc_qc_base_rom.sv" "$RTL/cofdm_qcldpc_sync_ram.sv" \
  "$RTL/cofdm_qcldpc_qc9_bram_decoder.sv"
verilator --lint-only -Wall --top-module cofdm_payload_codeword_bridge \
  "$RTL/cofdm_qcldpc_edge_rom.sv" "$RTL/cofdm_qcldpc_648_decoder.sv" "$RTL/cofdm_payload_codeword_bridge.sv"
verilator --lint-only -Wall --top-module cofdm_common_phase_rotator \
  "$RTL/cofdm_phase_lut.sv" "$RTL/cofdm_common_phase_rotator.sv"
verilator --lint-only -Wall -Wno-UNUSED -Wno-PINCONNECTEMPTY --top-module cofdm_pre_ldpc_symbol \
  "$RTL/cofdm_phase_lut.sv" "$RTL/cofdm_common_phase_rotator.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_pilot_phase_accum.sv" \
  "$RTL/cofdm_matched_llr.sv" "$RTL/cofdm_pre_ldpc_symbol.sv"
verilator --lint-only -Wall --top-module cofdm_pilot_phase_accum \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_pilot_phase_accum.sv"
verilator --lint-only -Wall --top-module cofdm_matched_llr "$RTL/cofdm_matched_llr.sv"
verilator --lint-only -Wall --top-module cofdm_ltf_channel_estimator \
  "$RTL/cofdm_ltf_freq_rom.sv" "$RTL/cofdm_ltf_channel_estimator.sv"
verilator --lint-only -Wall --top-module cofdm_ltf_channel_chain \
  "$RTL/cofdm_ltf_fft_stream_adapter.sv" "$RTL/cofdm_ltf_freq_rom.sv" \
  "$RTL/cofdm_ltf_channel_estimator.sv" "$RTL/cofdm_ltf_channel_chain.sv"
iverilog -g2012 -s tb_sync_pre_fft_frontend -o /tmp/cofdm_sync_pre_fft_tb \
  "$RTL/cofdm_stf_sync_frontend.sv" "$RTL/cofdm_cfo_angle_estimator.sv" \
  "$RTL/cofdm_cfo_control.sv" "$RTL/cofdm_cfo_nco_rotator.sv" \
  "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_sample_buffer.sv" \
  "$RTL/cofdm_ltf_time_matcher.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv" \
  "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/cofdm_ltf_sync_capture_frontend.sv" \
  "$RTL/cofdm_nco_ltf_sync_bridge.sv" "$RTL/cofdm_capture_ctrl.sv" \
  "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_fine_cfo_accum.sv" "$RTL/cofdm_ltf_fft_stream_adapter.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_fine_cfo_phase_to_inc.sv" \
  "$RTL/cofdm_ltf_fine_cfo_chain.sv" "$RTL/cofdm_sync_ltf_cfo_top.sv" \
  "$RTL/cofdm_pre_fft_replay_mem.sv" "$RTL/cofdm_pre_fft_replay.sv" "$RTL/cofdm_sync_pre_fft_frontend.sv" \
  "$RTL/tb/tb_sync_pre_fft_frontend.sv"
vvp /tmp/cofdm_sync_pre_fft_tb
verilator --lint-only -Wall --top-module cofdm_pre_fft_replay \
  "$RTL/cofdm_pre_fft_replay_mem.sv" "$RTL/cofdm_pre_fft_replay.sv"
verilator --lint-only -Wall --top-module cofdm_pre_fft_stream_replay \
  "$RTL/cofdm_pre_fft_replay_mem.sv" "$RTL/cofdm_pre_fft_stream_replay.sv"
verilator --lint-only -Wall -Wno-UNUSED -Wno-PINCONNECTEMPTY --top-module cofdm_sync_pre_fft_frontend \
  "$RTL/cofdm_stf_sync_frontend.sv" "$RTL/cofdm_cfo_angle_estimator.sv" \
  "$RTL/cofdm_cfo_control.sv" "$RTL/cofdm_cfo_nco_rotator.sv" \
  "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_sample_buffer.sv" \
  "$RTL/cofdm_ltf_time_matcher.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv" \
  "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/cofdm_ltf_sync_capture_frontend.sv" \
  "$RTL/cofdm_nco_ltf_sync_bridge.sv" "$RTL/cofdm_capture_ctrl.sv" \
  "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_fine_cfo_accum.sv" "$RTL/cofdm_ltf_fft_stream_adapter.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_fine_cfo_phase_to_inc.sv" \
  "$RTL/cofdm_ltf_fine_cfo_chain.sv" "$RTL/cofdm_sync_ltf_cfo_top.sv" \
  "$RTL/cofdm_pre_fft_replay_mem.sv" "$RTL/cofdm_pre_fft_replay.sv" "$RTL/cofdm_sync_pre_fft_frontend.sv"
verilator --lint-only -Wall -Wno-UNUSED -Wno-PINCONNECTEMPTY --top-module cofdm_sync_pre_fft_stream_frontend \
  "$RTL/cofdm_stf_sync_frontend.sv" "$RTL/cofdm_cfo_angle_estimator.sv" \
  "$RTL/cofdm_cfo_control.sv" "$RTL/cofdm_cfo_nco_rotator.sv" \
  "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_sample_buffer.sv" \
  "$RTL/cofdm_ltf_time_matcher.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv" \
  "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/cofdm_ltf_sync_capture_frontend.sv" \
  "$RTL/cofdm_nco_ltf_sync_bridge.sv" "$RTL/cofdm_capture_ctrl.sv" \
  "$RTL/cofdm_ltf_rot_rom.sv" "$RTL/cofdm_ltf_fine_cfo_accum.sv" "$RTL/cofdm_ltf_fft_stream_adapter.sv" \
  "$RTL/cofdm_cordic_atan2.sv" "$RTL/cofdm_fine_cfo_phase_to_inc.sv" \
  "$RTL/cofdm_ltf_fine_cfo_chain.sv" "$RTL/cofdm_sync_ltf_cfo_top.sv" \
  "$RTL/cofdm_pre_fft_replay_mem.sv" "$RTL/cofdm_pre_fft_stream_replay.sv" \
  "$RTL/cofdm_sync_pre_fft_stream_frontend.sv"
iverilog -g2012 -o /tmp/cofdm_ltf_search_ctrl_tb "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/tb/tb_ltf_search_ctrl.sv"
vvp /tmp/cofdm_ltf_search_ctrl_tb
verilator --lint-only -Wall --top-module cofdm_ltf_search_ctrl "$RTL/cofdm_ltf_search_ctrl.sv"
iverilog -g2012 -o /tmp/cofdm_ltf_sync_capture_tb \
  "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_sample_buffer.sv" "$RTL/cofdm_ltf_time_matcher.sv" \
  "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/cofdm_ltf_sync_capture_frontend.sv" \
  "$RTL/tb/tb_ltf_sync_capture_frontend.sv"
vvp /tmp/cofdm_ltf_sync_capture_tb
verilator --lint-only -Wall --top-module cofdm_ltf_sync_capture_frontend \
  "$RTL/cofdm_ltf_template_rom.sv" "$RTL/cofdm_ltf_sample_buffer.sv" \
  "$RTL/cofdm_ltf_time_matcher.sv" "$RTL/cofdm_ltf_time_matcher_tdm.sv" \
  "$RTL/cofdm_ltf_search_ctrl.sv" "$RTL/cofdm_ltf_sync_capture_frontend.sv"
iverilog -g2012 -o /tmp/cofdm_cfo_control_tb "$RTL/cofdm_cfo_control.sv" "$RTL/tb/tb_cfo_control.sv"
vvp /tmp/cofdm_cfo_control_tb
verilator --lint-only -Wall --top-module cofdm_cfo_control "$RTL/cofdm_cfo_control.sv"
iverilog -g2012 -o /tmp/cofdm_auto_sync_tb \
  "$RTL/cofdm_stf_sync_frontend.sv" "$RTL/cofdm_cfo_angle_estimator.sv" \
  "$RTL/cofdm_cfo_nco_rotator.sv" "$RTL/cofdm_cfo_control.sv" \
  "$RTL/cofdm_sync_frontend_auto_top.sv" "$RTL/tb/tb_sync_frontend_auto_top.sv"
vvp /tmp/cofdm_auto_sync_tb
verilator --lint-only -Wall -Wno-UNUSED --top-module cofdm_sync_frontend_auto_top \
  "$RTL/cofdm_stf_sync_frontend.sv" "$RTL/cofdm_cfo_angle_estimator.sv" \
  "$RTL/cofdm_cfo_nco_rotator.sv" "$RTL/cofdm_cfo_control.sv" \
  "$RTL/cofdm_sync_frontend_auto_top.sv"
bash "$ROOT/tests/run_pre_ldpc_stream_checks.sh"
# Payload end-to-end backend: variable lengths, multi-codeword frames,
# CRC/padding rejection, abort, malformed boundaries and ready/valid stalls.
iverilog -g2012 -s tb_payload_rx -o /tmp/cofdm_payload_rx_tb \
  "$RTL/cofdm_qcldpc_edge_rom.sv" "$RTL/cofdm_qcldpc_648_decoder.sv" \
  "$RTL/cofdm_payload_codeword_bridge.sv" "$RTL/cofdm_payload_postprocess.sv" \
  "$RTL/cofdm_payload_rx.sv" "$RTL/tb/tb_payload_rx.sv"
vvp /tmp/cofdm_payload_rx_tb
verilator --lint-only -Wall --top-module cofdm_payload_rx \
  "$RTL/cofdm_qcldpc_edge_rom.sv" "$RTL/cofdm_qcldpc_648_decoder.sv" \
  "$RTL/cofdm_payload_codeword_bridge.sv" "$RTL/cofdm_payload_postprocess.sv" \
  "$RTL/cofdm_payload_rx.sv"
echo "PASS all COFDM RTL checks"
