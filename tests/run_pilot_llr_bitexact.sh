#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MATLAB_BIN="/opt/Polyspace/R2020b/bin/matlab"
if [[ ! -x "$MATLAB_BIN" ]]; then
  echo "MATLAB not found at $MATLAB_BIN" >&2; exit 2
fi
cd "$ROOT"
"$MATLAB_BIN" -batch "addpath('matlab'); export_pilot_llr_vectors('matlab/vectors/pilot_llr')"
iverilog -g2012 -s tb_pilot_llr_bitexact -o /tmp/cofdm_pilot_llr_bitexact \
  matlab/rtl/cofdm_matched_llr.sv matlab/rtl/tb/tb_pilot_llr_bitexact.sv
vvp /tmp/cofdm_pilot_llr_bitexact
