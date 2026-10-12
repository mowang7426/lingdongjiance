#!/usr/bin/env python3
"""Wiring and persistence checks; native deltas run on macOS CI."""
from pathlib import Path
import plistlib
r = Path(__file__).resolve().parents[1]
s = (r/'Tweak.xm').read_text()
p = plistlib.loads((r/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())
for key in ('floatingTextOnlyShowUploadNetwork', 'floatingTextOnlyShowDownloadNetwork'):
    row, = [x for x in p['items'] if x.get('key') == key]
    assert row['default'] is False and row['cell'] == 'PSSwitchCell'
    assert row['defaults'] == 'com.yourname.sbcpufloating'
    assert row['get'] == 'getPreferenceValue:' and row['set'] == 'setPreferenceValue:specifier:'
    assert f'getBoolPref(CFSTR("{key}"), NO)' in s
    assert f'setBoolPref(CFSTR("{key}"), legacy)' in s
assert not any(x.get('key') == 'floatingTextOnlyShowNetwork' for x in p['items'])
assert 'if (!uploadPref && !downloadPref)' in s
assert 'getBoolPref(CFSTR("floatingTextOnlyShowNetwork"), NO)' in s
controller = (r/'sbcpuprefs/SBCPUTextOnlyController.m').read_text()
for api in ('CFPreferencesSetValue', 'CFPreferencesSynchronize', 'CFPreferencesCopyValue', 'notify_post'):
    assert api in controller
sampler = s[s.index('static void sampleTextNetwork(void) {'):s.index('static NSNumber *textOnlyBatteryCurrent')]
for required in ('floatingTextOnlyMode &&', '(textOnlyShowUploadNetwork || textOnlyShowDownloadNetwork)', '!cpuWindow.hidden', '!floatingView.hidden', 'AF_LINK', 'IFF_UP', 'IFF_RUNNING', 'IFF_LOOPBACK', 'freeifaddrs', 'systemUptime', 'hasBlankedScreen'):
    assert required in sampler, required
assert 'NSTimer' not in sampler and 'CADisplayLink' not in sampler
assert s.count('    sampleTextNetwork();') == 1
assert s.index('    sampleTextNetwork();') > s.index('- (void)updateDataWithCPU:(double)cpu\n')
assert 'wasUploadNetwork != textOnlyShowUploadNetwork' in s
assert 'wasDownloadNetwork != textOnlyShowDownloadNetwork' in s and 'resetTextNetwork();' in s
assert 'textOnlyLabel.text stringByAppendingFormat:@" %@", network' in s
assert 'textOnlyLabel.numberOfLines = 1' in s
assert 'SBCPUTextOnlyFitFont(naturalWidth, available, floatingTextOnlyFontSize)' in s
print('network OFF default, shared durable preferences, gated refresh and isolated layout: passed')
