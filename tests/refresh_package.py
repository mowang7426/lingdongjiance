import argparse
from pathlib import Path
import plistlib
root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--staged', type=Path)
a = p.parse_args()
filters = (root/'SBCPURefreshRate.plist').read_text()
assert 'com.apple.springboard' in filters
assert 'com.apple.UIKit' not in filters and 'UserNotificationsUIServer' not in filters
assert filters.count('"com.apple.') == 1
if a.staged:
    dylib, = a.staged.rglob('SBCPURefreshRate.dylib')
    plist, = a.staged.rglob('SBCPURefreshRate.plist')
    assert plist.read_text() == filters
    binary = dylib.read_bytes()
    for s in (b'SBCPURefreshRuntime',b'120diagnostic.request',b'callbackHz',b'originalCapability',b'pauseReason',b'preferredFrameRateRange'):
        # Selector begins setPreferred... on some builds; use stored range ABI audit string.
        assert s in binary or s == b'preferredFrameRateRange' and b'setPreferredFrameRateRange:' in binary, s
    bundle, = a.staged.rglob('SBCPUPrefs.bundle')
    rows = plistlib.loads((bundle/'Root.plist').read_bytes())['items']
    assert any(r.get('action') == 'show120HzDiagnostics' for r in rows)
print('PASS SpringBoard-only filter' + (' and packaged request/diagnostic runtime + homepage' if a.staged else ''))
