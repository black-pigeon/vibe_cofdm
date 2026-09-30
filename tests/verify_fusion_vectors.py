"""Independent integer checker for the MID fusion controller vectors."""
import csv
import json
from pathlib import Path


def rows(path):
    with path.open() as f:
        return [{k: int(v) for k, v in r.items()} for r in csv.DictReader(f)]


def verify(directory):
    manifest=json.loads((directory/'manifest.json').read_text())
    assert manifest['complete'] and len(manifest['cases'])==4
    for i, case in enumerate(manifest['cases']):
        x=rows(directory/f'case_{i}_input.csv')
        y=rows(directory/f'case_{i}_expected.csv')
        assert len(x)==200 and len(y)==200
        pilots=[r for r in x if r['pilot']]
        cre=sum(r['fresh_re']*r['old_re']+r['fresh_im']*r['old_im'] for r in pilots)
        cim=sum(r['fresh_im']*r['old_re']-r['fresh_re']*r['old_im'] for r in pilots)
        if abs(cre)>=abs(cim): rot=2 if cre<0 else 0
        else: rot=1 if cim>=0 else 3
        innovation=sum((r['fresh_re']-r['old_re'])**2+(r['fresh_im']-r['old_im'])**2 for r in pilots)
        variance=sum(r['old_var']+r['fresh_var'] for r in pilots)
        fast=innovation > 4*variance
        assert rot==case['rotation'] and fast==case['fast']
        for r,o in zip(x,y):
            fr,fi=r['fresh_re'],r['fresh_im']
            if rot==0: ar,ai=fr,fi
            elif rot==1: ar,ai=fi,-fr
            elif rot==2: ar,ai=-fr,-fi
            else: ar,ai=-fi,fr
            dr,di=ar-r['old_re'],ai-r['old_im']
            if fast: sr,si=dr,di
            else:
                # Python // is arithmetic floor, matching Verilog >>>.
                sr,si=dr//4,di//4
            nr=max(-(1<<17),min((1<<17)-1,r['old_re']+sr))
            ni=max(-(1<<17),min((1<<17)-1,r['old_im']+si))
            assert (nr,ni)==(o['next_re'],o['next_im']), (i,r['index'],nr,ni,o)
    print('PASS: four 200-carrier fusion controller vectors match independent integer reference')


if __name__ == '__main__':
    verify(Path(__file__).resolve().parents[1]/'vectors'/'fusion_ctrl')
