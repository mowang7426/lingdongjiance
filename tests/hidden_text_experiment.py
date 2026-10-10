from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
h=(r/'SBCPUHiddenTextExperiment.h').read_text()
rt=(r/'SBCPURefreshRuntime.h').read_text()
p=(r/'sbcpuprefs/SBCPUPrefsRootListController.m').read_text()
n=[x for x in plistlib.loads((r/'sbcpuprefs/Resources/Root.plist').read_bytes())['items'] if x.get('key')=='hiddenText120HzEnabled']
assert len(n)==1 and n[0]['default'] is False
for s in ('initWithFrame:CGRectZero', 'container.hidden = YES', 'text.hidden = YES', 'self.creating', 'self.attempted', 'UIStatusBarWindow', 'container.window == target', 'weak) UIWindow', 'removeFromSuperview', 'didMoveToWindow', 'self.container = nil', 'FAIL：未找到', 'self.initialized = YES'):
    assert s in h,s
assert h.count('[[UITextView alloc]')==1
assert h.index('if (!target)') < h.index('[[UITextView alloc]')
assert h.index('self.creating = YES') < h.index('[[UITextView alloc]')
assert h.index('self.container.detached = nil') < h.index('[self.container removeFromSuperview]')
for s in ('becomeFirstResponder', 'CADisplayLink', 'CADynamicFrameRateSource', 'MSHook', 'dispatch_after', 'NSTimer', 'performSelector', 'initWithDisplay:'):
    assert s not in h,s
for s in ('UIWindowDidBecomeVisibleNotification','UIWindowDidBecomeHiddenNotification','_enabled || _dynamicEnabled','hiddenTextExperiment','textEnabled','_textExperiment updateEnabled:'):
    assert s in rt,s
assert p.count('[key isEqualToString:@"hiddenText120HzEnabled"]')==2
assert 'hiddenTextExperiment' in p
print('PASS hidden text default OFF, public UIKit-only intervention, isolation, weak ownership, failclosed/lifecycle static contracts')
