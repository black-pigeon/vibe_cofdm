#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/.."
RTL="$ROOT/rtl"
SOURCES=(cofdm_phase_lut cofdm_common_phase_rotator cofdm_cordic_atan2
  cofdm_pilot_phase_accum cofdm_matched_llr cofdm_pre_ldpc_symbol
  cofdm_symbol_pilots cofdm_llr_packetizer cofdm_llr_fifo cofdm_pre_ldpc_stream)
FILES=()
for s in "${SOURCES[@]}"; do FILES+=("$RTL/$s.sv"); done
iverilog -g2012 -s tb_pre_ldpc_stream -o /tmp/cofdm_pre_ldpc_stream_tb \
  "${FILES[@]}" "$RTL/tb/tb_pre_ldpc_stream.sv"
vvp /tmp/cofdm_pre_ldpc_stream_tb
verilator --lint-only -Wall -Wno-UNUSED -Wno-PINCONNECTEMPTY \
  --top-module cofdm_pre_ldpc_stream "${FILES[@]}"
