#!/usr/bin/env python3
"""Independent integer/Fraction recomputation; not a replacement for native tests."""
from pathlib import Path
import plistlib, struct, hashlib
from fractions import Fraction
root = Path(__file__).resolve().parent / 'fixtures/a16'
expected = {'idle':1447.190419554883, 'load':2074.549863668391}
for name, target in expected.items():
    path = root / (name + '.plist')
    d = plistlib.loads(path.read_bytes())
    assert d['machine'] == 'iPhone15,3' and d['os'] == 'Version 17.0 (Build 21A329)'
    assert len(d['rawTables']) == 1 and d['rawTables'][0]['node'] == 'pmgr'
    p = d['rawTables'][0]['rawProperties']
    a, b = p['voltage-states5-sram'], p['voltage-states5']
    assert len(a) == len(b) == 136
    hz = [x[0] for x in struct.iter_unpack('<II', a)]
    assert hz[0] == 636000000 and hz[-1] == 3468000000 and all(x < y for x,y in zip(hz,hz[1:]))
    assert [x[0] for x in struct.iter_unpack('<II', b)] == [65536 * 10**9 // f for f in hz]
    rows = [r for r in d['channels'] if r['subgroup'] == 'CPU Core Performance States' and r['channel'] in ('PCPU0','PCPU1')]
    assert len(rows) == 2 and {r['channel'] for r in rows} == {'PCPU0','PCPU1'}
    assert len({r['driver'] for r in rows}) == 1 and {r['unit'] for r in rows} == {'24Mticks'}
    total = weighted = 0
    for r in rows:
        assert [s['name'] for s in r['states']] == ['IDLE'] + [f'V{k}P{16-k}' for k in range(17)]
        ticks = [s['residency'] for s in r['states'][1:]]
        assert all(t >= 0 for t in ticks)
        active = sum(ticks); numerator = sum(f*t for f,t in zip(hz,ticks))
        total += active; weighted += numerator
        print(name, r['channel'], 'activeTicks', active, 'MHz', float(Fraction(numerator, active*10**6)))
    result = Fraction(weighted, total * 10**6)
    assert abs(float(result)-target) < 1e-9
    print(name, 'sumActiveTicks', total, 'sumHzTicks', weighted, 'aggregateMHz', format(float(result),'.12f'), 'PASS')
    print('fixture SHA256', hashlib.sha256(path.read_bytes()).hexdigest())
print('A16 independent evidence fixture regression: PASS')
