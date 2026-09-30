#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIVADO=/opt/Xilinx/Vivado/2022.2/bin/vivado
mkdir -p "$ROOT/reports"
"$VIVADO" -mode batch -source "$ROOT/run_sim.tcl" -log "$ROOT/reports/vivado_sim.log" -journal "$ROOT/reports/vivado_sim.jou"
"$VIVADO" -mode batch -source "$ROOT/run_synth.tcl" -log "$ROOT/reports/vivado_synth.log" -journal "$ROOT/reports/vivado_synth.jou"
