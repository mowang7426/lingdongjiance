#!/usr/bin/env python3
"""Regression checks for embedding Insulation 0.1.38.1 in SBCPU."""
import argparse
import pathlib
import plistlib
R = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--staged', type=pathlib.Path)
args = p.parse_args()
# Insulation's original runtime is deliberately shipped in the same SBCPU package.
required = [
    'InsulationPayload/Library/MobileSubstrate/DynamicLibraries/insulation.dylib',
    'InsulationPayload/Library/MobileSubstrate/DynamicLibraries/insulation.plist',
    'InsulationPayload/Library/ControlCenter/Bundles/InsulationCC.bundle/InsulationCC',
    'InsulationPayload/usr/bin/insulationctl',
]
for rel in required:
    assert (R / rel).is_file(), f'Missing Insulation component: {rel}'
filter_plist = plistlib.loads((R / required[1]).read_bytes())
assert 'thermalmonitord' in str(filter_plist), 'Insulation hook must target thermalmonitord'
root = plistlib.loads((R / 'sbcpuprefs/Resources/Root.plist').read_bytes())
rows = root.get('items', [])
labels = [row.get('label') for row in rows]
expected = ['CPU 模式', '防止温控暗屏', '禁温度计弹窗', '禁用口袋高温', '锁定阳光暴晒']
for label in expected:
    assert label in labels, f'Missing original Insulation setting: {label}'
source_index = labels.index('🌐 莫忘越狱源')
assert all(labels.index(label) < source_index for label in expected), 'Insulation settings must appear above MoWang source row'
expected_keys = {
    'thermalPowerMode', 'thermalPreventDimmingEnabled',
    'thermalSuppressNotificationsEnabled', 'thermalDisablePocketSunlightEnabled',
    'thermalSunlightLockedEnabled'
}
found = {row.get('key') for row in rows if row.get('key')}
assert expected_keys <= found, f'Missing setting keys: {expected_keys - found}'
prefs = (R / 'sbcpuprefs/SBCPUPrefsRootListController.m').read_text()
assert 'com.be-huge.insulation-prefs' in prefs
assert 'com.be-huge.insulation-executePuppetEvent' in prefs
makefile = (R / 'Makefile').read_text()
for component in ['insulation.dylib', 'insulation.plist', 'InsulationCC.bundle', 'insulationctl']:
    assert component in makefile, f'Not staged by package Makefile: {component}'
# Ensure original SBCPU charging implementation remains present and not rewritten by this integration.
for rel in ['SBCPUChargeEngine.m', 'SBCPUChargeDaemon.m', 'SBCPUPowerd.xm']:
    assert (R / rel).is_file(), f'Missing SBCPU charging component: {rel}'
if args.staged:
    for rel in ['Library/MobileSubstrate/DynamicLibraries/insulation.dylib',
                'Library/MobileSubstrate/DynamicLibraries/insulation.plist',
                'Library/ControlCenter/Bundles/InsulationCC.bundle/InsulationCC',
                'usr/bin/insulationctl']:
        assert list(args.staged.rglob(pathlib.Path(rel).name)), f'Missing staged component: {rel}'
print('PASS: original Insulation settings and runtime components are integrated into SBCPU package source')
