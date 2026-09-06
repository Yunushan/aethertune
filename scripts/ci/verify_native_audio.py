#!/usr/bin/env python3
"""Verify real decoded PCM at the isolated Linux virtual sink, not speakers."""

from __future__ import annotations

import argparse
import array
import json
import math
from pathlib import Path
import sys


def inspect_pcm(path: Path) -> dict[str, object]:
    size = path.stat().st_size
    if size < 44100 or size > 256 * 1024 * 1024 or size % 2:
        raise ValueError('Expected bounded mono s16le PCM with at least one second of data.')
    samples = active = peak = squared = 0
    with path.open('rb') as stream:
        while block := stream.read(65536):
            values = array.array('h')
            values.frombytes(block)
            if sys.byteorder != 'little':
                values.byteswap()
            samples += len(values)
            for value in values:
                peak = max(peak, abs(value))
                squared += value * value
                if abs(value) >= 100:
                    active += 1
    if peak < 500 or active < 22050 // 4:
        raise ValueError('No sustained non-silent decoded audio reached the virtual sink.')
    return {
        'status': 'passed',
        'format': 's16le/mono/22050Hz',
        'samples': samples,
        'peak': peak,
        'rms': round(math.sqrt(squared / samples), 3),
        'active_samples': active,
        'scope': 'Decoded PCM in a private virtual sink; not physical acoustic output.',
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pcm', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    report = inspect_pcm(args.pcm)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
