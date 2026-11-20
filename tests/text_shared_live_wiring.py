#!/usr/bin/env python3
"""Source gate; actual glyph/mask state is exercised by text_shared_live_uikit."""
from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1]
s=(r/'SBCPUTextBackdropLabel.m').read_text();t=(r/'Tweak.xm').read_text()
assert s.count('SBCPUCreateLiveTextBackdrop(SBCPUSharedBlurRadius, YES)')==1
assert 'SBCPUSharedBlurRadius = 8.0' in s
assert 'SBCPUCreateLiveTextBackdrop(50.0, NO)' in s
assert 'CGRectUnion(region,' in s and 'CGFloat pad = 1.0 / scale' in s
assert 'ceil(CGRectGetMaxX(region)*scale)' in s
assert 'sbcpu_alphaMaskMatchesScale:scale' in s
assert 'if (refresh || !_sbcpuSharedGlyph)' in s
assert 'if (!CGRectEqualToRect(_sbcpuBackdrop.frame, region))' in s
assert 'if (_sbcpuMask.contentsScale != scale)' in s
assert 'backdrop.filters = filters' in s and s.count('backdrop.filters = filters')==1
assert 'shared && ![backdrop.filters isEqualToArray:filters]' in s
assert t.count('[[SBCPUTextSlotHost alloc] initWithFrame:CGRectZero]')==2
for word in ('CADisplayLink','NSTimer','snapshotView','drawViewHierarchy','renderInContext:'):
    assert word not in s
# All unrelated production data, layout policies, settings, charging and
# build inputs remain byte-for-byte mem5. Tweak changes are reviewed separately.
changed=subprocess.check_output(['git','diff','--name-only','eedb71d7af144dd5ac542f03158c277162762efb'],cwd=r,text=True).splitlines()
allowed={'SBCPUTextBackdropLabel.h','SBCPUTextBackdropLabel.m','Tweak.xm','control','.github/workflows/build.yml'}
assert all(p in allowed or p.startswith(('tests/','README_V5.09_MEM6')) for p in changed),changed
assert 'text_shared_live_uikit.sh' in (r/'.github/workflows/build.yml').read_text()
print('PASS mem6 one host per HUD, 8pt shared/50pt mem5 fallback, glyph-ink union, cache, isolated production scope')
