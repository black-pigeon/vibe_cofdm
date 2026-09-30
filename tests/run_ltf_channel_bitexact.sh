#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MATLAB_BIN="/opt/Polyspace/R2020b/bin/matlab"
if [[ ! -x "$MATLAB_BIN" ]]; then
  echo "MATLAB not found at $MATLAB_BIN" >&2; exit 2
fi
cd "$ROOT"
"$MATLAB_BIN" -batch "addpath('matlab'); export_ltf_channel_vectors('matlab/vectors/ltf_channel')"
iverilog -g2012 -s tb_ltf_channel_bitexact -o /tmp/cofdm_ltf_channel_bitexact \
  matlab/rtl/cofdm_ltf_freq_rom.sv matlab/rtl/cofdm_ltf_channel_estimator.sv \
  matlab/rtl/tb/tb_ltf_channel_bitexact.sv
vvp /tmp/cofdm_ltf_channel_bitexact
