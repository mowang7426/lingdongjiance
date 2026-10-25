from pathlib import Path
import plistlib, subprocess
root=Path(__file__).resolve().parents[1]
base='9eb7e4947e976da22a15c1945a598ce0f81afb63'
for name in ['Tweak.xm','SBCPUPowerd.xm','SBCPUPCoreFrequency.m','SBCPUChargeEngine.m','SBCPUFloating.plist','SBCPUPowerd.plist']:
    assert (root/name).read_bytes()==subprocess.check_output(['git','show',base+':'+name],cwd=root),name
p=root/'PeachDock'
t=(p/'SBCPUPeachDock.m').read_text()
assert 'OBJC_ASSOCIATION_ASSIGN' not in t
assert 'exactFourIconModel' not in t and 'likelyStockDockModel' not in t
assert 'CFPreferencesCopy' not in t
assert t.index('if (!SBCPUPeachDockProfileApproved') < t.index('SBCPUPeachDockInstallHook(object_getClass(dockClass)')
assert 'SBCPUPeachDockPitch(CGRectGetWidth(list.bounds))' in t
assert 'SBCPUPeachDockIconPitch(self)' in (p/'SBCPUPeachDockDockDropMapping.h').read_text()
e=(p/'SBCPUPeachDockEdgeTransition.m').read_text()
assert 'SBCPUPeachDockEffects()' in e and 'if (pending >= 2)' in e
assert '[_displayLink invalidate]' in e and 'MaximumSamples = 12' in e
items=plistlib.loads((root/'sbcpuprefs/Resources/Root.plist').read_bytes())['items']
assert sum(i.get('detail')=='SBCPUPeachDockController' for i in items)==1
assert 'Version: 5.09+peach1' in (root/'control').read_text()
assert (root/'SBCPUPeachDock.plist').read_text().strip()=='{ Filter = { Bundles = ("com.apple.springboard"); }; }'
print('PASS: preserved 5.08 production core, weak ownership, snapshot, closed gate, settings, filter')
