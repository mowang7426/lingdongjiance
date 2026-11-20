#!/usr/bin/env python3
"""Build pinned mem5 with only symbol isolation (uses its original test backend)."""
import hashlib
import json
import pathlib
import subprocess
import sys

base = 'eedb71d7af144dd5ac542f03158c277162762efb'
tree = '2f27d2e105b62e35c545b434a6ff35e6593b4095'
root = pathlib.Path(__file__).resolve().parents[1]
out = pathlib.Path(sys.argv[1])
assert subprocess.check_output(['git', 'rev-parse', base + '^{tree}'], cwd=root).decode().strip() == tree
hashes = {}
for ext in ('m', 'h'):
    filename = f'SBCPUTextBackdropLabel.{ext}'
    raw = subprocess.check_output(['git', 'show', f'{base}:{filename}'], cwd=root)
    hashes[filename] = hashlib.sha256(raw).hexdigest()
    text = raw.decode()
    for symbol in ('SBCPUTextBackdrop', 'SBCPUCapsuleBackdropLabel', 'SBCPUTextAlphaMask', 'gSBCPUBackdropTestCounters'):
        text = text.replace(symbol, symbol.replace('SBCPU', 'SBCPUMem5', 1))
    (out / f'SBCPUMem5TextBackdropLabel.{ext}').write_text(text)
(root / 'test-output').mkdir(exist_ok=True)
(root / 'test-output/mem5-baseline-source.json').write_text(json.dumps({
    'commit': base, 'tree': tree, 'sha256': hashes, 'adaptations': ['symbol isolation for concurrent execution'],
    'backend': 'pinned mem5 simulator CALayer surrogate with original production glyph renderer',
}, indent=2) + '\n')
