#!/usr/bin/env python3
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
s = (root / 'SBCPUPCoreFrequency.m').read_text()
t = (root / 'Tweak.xm').read_text()
for bad in ('IORegistryEntrySet', 'IOConnectCall', 'sleepForTimeInterval', 'NSTimer', 'dispatch_source_create', 'for (;;)', 'maxFreqMHz', 'voltage-states1'):
    assert bad not in s, bad
for good in ('mach_continuous_time()', 'elapsed > 5', 'elapsed < 0.5', 'CFRelease(previous)', 'CFRelease(subscription)', 'CFRelease(subscribed)', 'CFRelease(delta)', 'now - requestedAt >= 0.9', 'cachedMHz = mhz', 'now - cachedEnd <= 3', 'hasBlankedScreen', 'r < 0', 'PTopology(deltaRows)', 'PCPU[0-9]+'):
    assert good in s, good
assert 'readDVFSTable' not in t and 'readFrequencyFromIOReport' not in t
assert t.count('return SBCPUReadPcoreFrequency();') == 1
assert ': @"频 --"' in t and ': @"--MHz"' in t and ': @"-- MHz"' in t
assert 'frequencyNeeded ? getRealCPUFrequency(cpu) : 0.0' in t
# Existing refresh, frame counter, touch policy and every unrelated source stay identical.
base = subprocess.check_output(['git', 'show', '35886cf95936787b8d98ea5bce0a4964f0a0cc8d:Tweak.xm'], cwd=root, text=True)
for start, end in [('static void updateTextNetwork(', 'static BOOL statusDockShowFrequency'),
                   ('static double getSpringBoardCPUUsage(', '// 当前频率 = IOReport P-State residency')]:
    if start not in base or start not in t or end not in t: continue
    assert base[base.index(start):base.index(end, base.index(start))] == t[t.index(start):t.index(end, t.index(start))]
assert base.count('scheduledTimerWithTimeInterval:') == t.count('scheduledTimerWithTimeInterval:')
assert 'Version: 5.09+full3\n' in (root / 'control').read_text()
for good in ('PStructuralTable', 'PComputeMapped(deltaRows', 'iPhone15,3', 'unverified-chip-mapping', '65536000000000ULL / hz', 'states.count != frequencies.count + 1', 'names.count != 2', 'now - diagnosticTime < 300'):
    assert good in s, good
assert '@"channels":rows' not in s and '@"rawTables":tables' not in s
print('P-core read-only wiring/lifecycle/scope: PASS')
