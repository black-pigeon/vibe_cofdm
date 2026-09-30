#!/usr/bin/env python3
"""Check RTL T1*conj(T2) ROM against the same ZC roots as training.m."""
import cmath, math, re
from pathlib import Path
root = Path(__file__).resolve().parents[1]
sv = (root / "rtl/cofdm_ltf_rot_rom.sv").read_text()
pat = re.compile(r"8'd(\d+): begin re=(-?16'sd\d+); im=(-?16'sd\d+); end")
def val(s): return int(s.replace("16'sd", ""))
got = {int(a):(val(b),val(c)) for a,b,c in pat.findall(sv)}
active = list(range(-100,0))+list(range(1,101))
z=[]
for root_zc in (25,29):
    x=[cmath.exp(-1j*math.pi*root_zc*n*(n+1)/201) for n in range(201)]
    x.pop(100); z.append({k:x[i] for i,k in enumerate(active)})
def q(x):
    y=int(math.floor(x*32768+.5) if x>=0 else math.ceil(x*32768-.5))
    return max(-32768,min(32767,y))
for k in active:
    v=z[0][k]*z[1][k].conjugate(); e=(q(v.real),q(v.imag))
    if got.get(k%256)!=e: raise SystemExit(f"ROM mismatch bin {k%256}: got={got.get(k%256)} expected={e}")
if len(got)!=200: raise SystemExit(f"expected 200 entries, got {len(got)}")
print("PASS dual-LTF rotation ROM matches MATLAB T1*conj(T2) (200 bins)")
