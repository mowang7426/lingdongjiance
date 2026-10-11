#!/usr/bin/env python3
"""Wiring and persistence checks; native deltas run on macOS CI."""
from pathlib import Path
import plistlib
r = Path(__file__).resolve().parents[1]
s = (r/'Tweak.xm').read_text()
p = plistlib.loads((r/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())
row, = [x for x in p['items'] if x.get('key') == 'floatingTextOnlyShowNetwork']
assert row['default'] is False and row['cell'] == 'PSSwitchCell'
assert row['defaults'] == 'com.yourname.sbcpufloating'
assert row['get'] == 'getPreferenceValue:' and row['set'] == 'setPreferenceValue:specifier:'
assert 'getBoolPref(CFSTR("floatingTextOnlyShowNetwork"), NO)' in s
controller = (r/'sbcpuprefs/SBCPUTextOnlyController.m').read_text()
for api in ('CFPreferencesSetValue', 'CFPreferencesSynchronize', 'CFPreferencesCopyValue', 'notify_post'):
    assert api in controller
sampler = s[s.index('static void sampleTextNetwork(void) {'):s.index('static NSNumber *textOnlyBatteryCurrent')]
for required in ('floatingTextOnlyMode && textOnlyShowNetwork', '!cpuWindow.hidden', '!floatingView.hidden', 'AF_LINK', 'IFF_UP', 'IFF_RUNNING', 'IFF_LOOPBACK', 'freeifaddrs', 'systemUptime', 'hasBlankedScreen'):
    assert required in sampler, required
assert 'NSTimer' not in sampler and 'CADisplayLink' not in sampler
assert s.count('    sampleTextNetwork();') == 1
assert s.index('    sampleTextNetwork();') > s.index('- (void)updateDataWithCPU:(double)cpu\n')
assert 'wasNetwork != textOnlyShowNetwork' in s and 'resetTextNetwork();' in s
assert 'textOnlyLabel.text stringByAppendingFormat:@" %@", network' in s
assert 'textOnlyLabel.numberOfLines = 1' in s
assert 'SBCPUTextOnlyFitFont(naturalWidth, available, floatingTextOnlyFontSize)' in s
print('network OFF default, shared durable preferences, gated refresh and isolated layout: passed')
