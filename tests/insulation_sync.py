#!/usr/bin/env python3
"""Source-level contracts for precompiled InsulationCC interoperability (no iOS SDK)."""
import pathlib
import plistlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
src = (root / 'sbcpuprefs/SBCPUPrefsRootListController.m').read_text()
make = (root / 'sbcpuprefs/Makefile').read_text()
package = (root / 'Makefile').read_text()
binary = (root / 'InsulationPayload/Library/ControlCenter/Bundles/InsulationCC.bundle/InsulationCC').read_bytes()

def body(signature):
    start = src.index(signature)
    start = src.index('{', start) + 1
    depth = 1
    for i in range(start, len(src)):
        depth += (src[i] == '{') - (src[i] == '}')
        if not depth:
            return src[start:i]
    raise AssertionError(signature)

for name in ('com.be-huge.insulation-prefs.plist', 'thermalPowerMode',
             'com.be-huge.insulation.runtimeState',
             'com.be-huge.insulation-executePuppetEvent',
             'com.be-huge.insulation-restartThermalMonitor'):
    assert name.encode() in binary, f'CC does not contain {name}'
    assert name in src, f'Settings does not contain {name}'
assert 'jbroot([InsulationPrefsPath UTF8String])' in src
assert 'dictionaryWithContentsOfFile:path' in body('static NSDictionary *InsulationReadPrefs')
read = body('static NSDictionary *InsulationReadPrefs')
write = body('static BOOL InsulationWritePref')
assert 'writeToFile:' not in read and 'CFPreferences' not in read
assert 'CFPreferences' not in write and 'CFPreferencesSetValue' not in body('- (void)setPreferenceValue:') .split('if ([key isEqualToString:@"respringPreserveNativeUnlockEnabled"])')[0]
assert 'if (ok)' in write and 'if (flock(fd, LOCK_EX) != 0)' in write
assert 'exists ? [NSMutableDictionary dictionaryWithContentsOfFile:path]' in write
assert 'BOOL ok = prefs != nil' in write
assert 'chown(' in write and 'chmod(' in write
getter = body('- (id)getPreferenceValue:')
popup = body('- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:')
assert 'InsulationReadPrefs()' in getter and 'InsulationModeTitle(InsulationMode(prefs))' in getter
assert 'InsulationMode(InsulationReadPrefs())' in popup
assert 'CFPreferencesCopyValue' not in popup
setter = body('- (void)setPreferenceValue:')
insulation = setter.split('if ([key isEqualToString:@"respringPreserveNativeUnlockEnabled"])')[0]
assert 'if (InsulationWritePref(key, value))' in insulation
assert insulation.index('InsulationRuntimeNotify') < insulation.index('insulation-executePuppetEvent') < insulation.index('insulation-restartThermalMonitor')
assert 'if ([key isEqualToString:@"thermalPowerMode"])' in insulation
assert 'notify_register_dispatch' in body('- (void)viewDidLoad')
assert 'notify_cancel(_insulationNotifyToken)' in body('- (void)dealloc')
assert '(__bridge const void *)self' not in src, 'No unretained controller pointer in Darwin callback'
assert 'UIApplicationWillEnterForegroundNotification' in src
assert 'dispatch_get_main_queue()' in src and '__weak' in src
assert 'reloadSpecifiers' in body('- (void)viewWillAppear:')
assert re.search(r'ifeq \(\$\(THEOS_PACKAGE_SCHEME\),roothide\).*?SBCPUPrefs_LDFLAGS \+= .*?-lroothide', make, re.S)
assert 'InsulationCC.bundle/InsulationCC' in package
print('PASS: CC binary strings, file-store contracts, notifications, refresh and roothide link')
