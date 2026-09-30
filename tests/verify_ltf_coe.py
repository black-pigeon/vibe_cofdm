#!/usr/bin/env python3
"""Check that the Vivado COE contains the same Q1.15 LTF as the RTL ROM."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sv = (root / "rtl/cofdm_ltf_template_rom.sv").read_text()
coe = (root / "vivado/cofdm_ltf_sync_ref/cofdm_ltf_template.coe").read_text()
pat = r"8'd(\d+): begin re=(-?)(?:16'sd)(\d+); im=(-?)(?:16'sd)(\d+); end"
sv_vals = {
    int(a): (((-1 if sr else 1) * int(vr)) & 0xFFFF) << 16
    | ((-1 if si else 1) * int(vi) & 0xFFFF)
    for a, sr, vr, si, vi in re.findall(pat, sv)
}
coe_vals = [int(x, 16) for x in re.findall(r"\b[0-9A-Fa-f]{8}\b", coe)]
if len(sv_vals) != 256 or len(coe_vals) != 256:
    raise SystemExit(f"entry count mismatch SV={len(sv_vals)} COE={len(coe_vals)}")
if any(sv_vals[i] != coe_vals[i] for i in range(256)):
    bad = next(i for i in range(256) if sv_vals[i] != coe_vals[i])
    raise SystemExit(f"COE mismatch at address {bad}")
print("PASS LTF COE matches RTL ROM (256 words)")
