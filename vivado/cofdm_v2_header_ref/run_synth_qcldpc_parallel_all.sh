#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
VIVADO=${VIVADO:-/opt/Xilinx/Vivado/2022.2/bin/vivado}
for LANES in 3 9 27; do
  "$VIVADO" -mode batch -source "$SCRIPT_DIR/run_synth_qcldpc_parallel.tcl" \
    -tclargs "$LANES"
done
