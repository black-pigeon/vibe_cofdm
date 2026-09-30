"""Verify exported FIR fixtures using Python integers only (no MATLAB/NumPy)."""
import csv
import json
from pathlib import Path


def rounded_shift(value, bits):
    sign = -1 if value < 0 else 1
    return sign * ((abs(value) + (1 << (bits - 1))) >> bits)


def saturate(value, bits):
    return max(-(1 << (bits - 1)), min((1 << (bits - 1)) - 1, value))


def rotate(value, coefficient, bits, fraction):
    a, b = value
    c, d = coefficient
    return tuple(saturate(rounded_shift(x, fraction), bits)
                 for x in (a * c - b * d, a * d + b * c))


def read_rows(path):
    with path.open() as stream:
        return [{k: int(v) for k, v in row.items()}
                for row in csv.DictReader(stream)]


def verify(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    bits, frac = manifest['dataBits'], manifest['coefficientFractionBits']
    data = {r['signed_carrier']: (r['i_s18_f14'], r['q_s18_f14'])
            for r in read_rows(directory / 'fir_input.csv')}
    expected = {r['signed_carrier']: (r['i_s18_f14'], r['q_s18_f14'])
                for r in read_rows(directory / 'fir_expected.csv')}
    rotation = {r['phase_mod16']: (r['i_s18_f16'], r['q_s18_f16'])
                for r in read_rows(directory / 'rotation_rom.csv')}
    normalization = {r['signed_carrier']: r for r in
                     read_rows(directory / 'normalization_rom.csv')}
    assert set(data) == set(range(-100, 101)) - {0}
    assert set(data) == set(expected)
    assert set(rotation) == set(range(16))
    centered = {k: rotate(v, rotation[k % 16], bits, frac)
                for k, v in data.items()}
    for k in data:
        total = [0, 0]
        weight = 0
        for shift, tap in zip(range(-3, 4), manifest['kernel']):
            if k + shift in centered:
                weight += tap
                for component in range(2):
                    total[component] += tap * centered[k + shift][component]
        assert weight == normalization[k]['weight']
        reciprocal = normalization[k]['reciprocal_s18_f16']
        assert reciprocal == ((1 << frac) + weight // 2) // weight
        smooth = tuple(saturate(rounded_shift(
            saturate(v, manifest['accumulatorBits']) * reciprocal, frac), bits)
            for v in total)
        real, imag = rotation[k % 16]
        actual = rotate(smooth, (real, -imag), bits, frac)
        assert actual == expected[k], (k, actual, expected[k])
    pilots = read_rows(directory / 'pilot_rom.csv')
    assert len(pilots) == 72
    assert len({(r['pilot_carrier'], r['candidate_zero_based']) for r in pilots}) == 72
    print(f'PASS: all {len(data)} complex FIR outputs match Python integer reference; '
          'pilot ROM shape checked (pilot processing remains float).')


if __name__ == '__main__':
    verify(Path(__file__).resolve().parents[1] / 'vectors' / 'receiver_fixed')
