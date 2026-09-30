#!/usr/bin/env python3
"""Check the RTL dual-LTF frequency ROM against training.m's ZC definition."""
import cmath, math, re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sv = (root / "rtl/cofdm_ltf_freq_rom.sv").read_text()
pat = re.compile(r"8'd(\d+): begin t1_re=(-?16'sd\d+); t1_im=(-?16'sd\d+); "
                 r"t2_re=(-?16'sd\d+); t2_im=(-?16'sd\d+); end")
def val(x):
    return int(x.replace("16'sd", ""))
got = {int(a): tuple(val(x) for x in (b,c,d,e)) for a,b,c,d,e in pat.findall(sv)}
active = list(range(-100, 0)) + list(range(1, 101))
expected = {}
for root_zc, key in ((25, 0), (29, 2)):
    z = [cmath.exp(-1j * math.pi * root_zc * n * (n + 1) / 201) for n in range(201)]
    z.pop(100)
    for k, x in zip(active, z):
        b = k % 256
        q = lambda y: max(-32768, min(32767, int(math.floor(y * 32768 + .5) if y >= 0 else math.ceil(y * 32768 - .5))))
        expected.setdefault(b, [0, 0, 0, 0])[key:key+2] = [q(x.real), q(x.imag)]
for b, e in expected.items():
    if got.get(b) != tuple(e):
        raise SystemExit(f"ROM mismatch bin {b}: got={got.get(b)} expected={tuple(e)}")
if len(got) != 200:
    raise SystemExit(f"expected 200 active ROM entries, got {len(got)}")
print("PASS dual-LTF frequency ROM matches MATLAB ZC definition (200 bins)")
