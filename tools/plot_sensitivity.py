"""Render completed sensitivity experiments; no synthetic or fitted PER points."""
import csv
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

root = Path(__file__).resolve().parents[1] / 'results'
output = root / 'figures'
output.mkdir(exist_ok=True)


def read(name):
    path = root / name
    assert json.loads(Path(str(path) + '.json').read_text())['complete'], name
    with path.open() as stream:
        return list(csv.DictReader(stream))


screen = read('sensitivity_screen.csv')
confirmed = sum((read(name) for name in [
    'sensitivity_confirm.csv', 'sensitivity_cp_confirm.csv',
    'sensitivity_awgn_confirm.csv']), [])
colors = {'awgn': '#2472b4', 'short': '#cf6a24', 'cp_edge': '#7353a6'}
labels = {'awgn': 'AWGN', 'short': 'Short multipath', 'cp_edge': 'CP-edge multipath'}
plt.rcParams.update({'font.size': 10, 'axes.spines.top': False, 'axes.spines.right': False})

fig, (ax, bars) = plt.subplots(1, 2, figsize=(13, 5.2), layout='constrained')
for channel, color in colors.items():
    screening = [r for r in screen if r['channel'] == channel]
    ax.plot([float(r['sample_snr_db']) for r in screening],
            [float(r['per']) if int(r['errors']) else np.nan for r in screening],
            ':', color=color, alpha=.6, label=labels[channel])
    for r in [r for r in confirmed if r['channel'] == channel]:
        x, y = float(r['sample_snr_db']), float(r['per'])
        if int(r['errors']):
            ax.errorbar(x, y, yerr=[[y - float(r['ci95_low'])], [float(r['ci95_high']) - y]],
                        fmt='o', color=color, capsize=3)
        else:
            ax.scatter(x, float(r['upper95']), marker='v', color=color, s=65)
ax.axhline(.01, color='#666666', lw=1, ls='--')
ax.set(yscale='log', ylim=(.0005, 1.25), xlim=(-.15, 7.2),
       xlabel='Complex-sample SNR (dB)', ylabel='Packet error rate',
       title='1500-byte PHY payload, v2 compact')
ax.grid(True, which='both', alpha=.16)
ax.legend(loc='lower left')

ordered = sorted(confirmed, key=lambda r: (list(colors).index(r['channel']), float(r['sample_snr_db'])))
bottom = np.zeros(len(ordered))
for field, label, color in [('sync_failures', 'Acquisition', '#d45b4c'),
                            ('header_failures', 'Header', '#cfa42a'),
                            ('payload_failures', 'Payload', '#2879a8')]:
    values = np.array([100 * int(r[field]) / int(r['frames']) for r in ordered])
    bars.bar(range(len(ordered)), values, bottom=bottom, label=label, color=color)
    bottom += values
bars.set_xticks(range(len(ordered)),
                [r['channel'] + '\n' + r['sample_snr_db'] + ' dB' for r in ordered], fontsize=8)
bars.set(ylabel='Failed captures (%)', title='Failure stages: independent 300-frame points')
bars.legend()
bars.grid(axis='y', alpha=.16)
fig.suptitle('Model evaluation: QPSK, LDPC(648,324), 12 iterations, static channels', fontsize=13)
fig.supxlabel('Left: dotted = 60-frame screening; circles = 300-frame PER with two-sided 95% CI.\n'
              'Down triangles = one-sided 95% upper bounds for 0/300, NOT observed nonzero PER.', fontsize=9)
for ext in ('png', 'svg'):
    fig.savefig(output / f'sensitivity_per.{ext}', dpi=180)
plt.close(fig)

oracle = read('sensitivity_oracle.csv')
oc = read('sensitivity_oracle_confirm.csv')[0]
fig, ax = plt.subplots(figsize=(8, 5), layout='constrained')
ax.plot([float(r['sample_snr_db']) for r in oracle],
        [float(r['full_per']) for r in oracle], 'o-', label='Full RX, 40 paired captures', color='#2472b4')
ax.plot([float(r['sample_snr_db']) for r in oracle],
        [float(r['oracle_per']) for r in oracle], 's-', label='Oracle payload, same 40 captures', color='#cf6a24')
x, y = float(oc['sample_snr_db']), float(oc['oracle_per'])
ax.errorbar(x, y, yerr=[[y - float(oc['oracle_ci95_low'])], [float(oc['oracle_ci95_high']) - y]],
            fmt='D', color='#7353a6', capsize=5, label='Oracle: independent 300-frame check')
ax.set(xlabel='Complex-sample SNR (dB)', ylabel='Packet error rate', ylim=(-.04, 1.05),
       title='AWGN diagnostic: perfect timing/channel vs full receiver')
ax.grid(alpha=.18)
ax.legend()
fig.supxlabel('Oracle knows timing, CFO, channel, noise variance and length; it bypasses the header.\n'
              'This is a diagnostic reference, not an implementable receiver or a promised gain.', fontsize=9)
for ext in ('png', 'svg'):
    fig.savefig(output / f'sensitivity_oracle.{ext}', dpi=180)
plt.close(fig)
print('Saved sensitivity_per and sensitivity_oracle as PNG/SVG in', output)
