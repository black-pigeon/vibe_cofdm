#!/usr/bin/env bash
set -euo pipefail
VIVADO=/opt/Xilinx/Vivado/2022.2/bin/vivado
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$VIVADO" -mode batch -source "$ROOT/run_sim.tcl"
"$VIVADO" -mode batch -source "$ROOT/run_synth.tcl"
