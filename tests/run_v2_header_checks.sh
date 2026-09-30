#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/.."
/opt/Polyspace/R2020b/bin/matlab -batch "addpath('matlab'); export_v2_header_vectors"
bash matlab/rtl/run_checks.sh >/tmp/cofdm_v2_header_checks.log 2>&1
grep -E 'PASS .*v2 Header|PASS all COFDM' /tmp/cofdm_v2_header_checks.log
