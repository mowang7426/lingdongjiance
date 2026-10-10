#!/usr/bin/env python3
"""Public request/diagnostic lifecycle contract, not proof of physical 120Hz."""
from pathlib import Path
import plistlib
import re
root = Path(__file__).resolve().parents[1]
source = (root / 'MotionXPort.xm').read_text()
runtime = (root / 'SBCPURefreshRuntime.h').read_text()
makefile = (root / 'Makefile').read_text()
prefs = (root / 'sbcpuprefs/SBCPUPrefsRootListController.m').read_text()
assert 'TARGET = iphone:clang:16.5:14.0' in makefile
assert '%hook' not in source and 'MSHookMessageEx' not in runtime
assert 'return original >= 120' not in source
assert 'com.apple.springboard' in source and 'dispatch_async(dispatch_get_main_queue()' in source
for arg in ('@encode(void)', '@encode(NSInteger)', '@encode(CAFrameRateRange)', 'sig.numberOfArguments == 3', 'getArgumentTypeAtIndex:2'):
    assert arg in runtime
assert re.search(r'if \(@available\(iOS 15\.0, \*\)\)\s*\{\s*if \(_rangeABI\)\s*\{\s*_link.preferredFrameRateRange', runtime)
assert 'CAFrameRateRangeMake(120.0f,120.0f,120.0f)' in runtime
assert '[_link invalidate]; _link = nil;' in runtime
assert 'NSRunLoopCommonModes' in runtime
assert 'notify_get_state' in runtime and 'com.apple.springboard.lockstate' in runtime
assert 'com.apple.iokit.hid.displayStatus' in runtime
assert 'NSProcessInfoPowerStateDidChangeNotification' in runtime
assert 'NSProcessInfoThermalStateDidChangeNotification' in runtime
assert 'self->_enabled = SBCPU120HzEnabled(); self->_dynamicEnabled = SBCPUDynamic120HzEnabled(); [self updateRequest];' in runtime
assert 'SBCPURefreshHardware120(model)' in runtime
start = runtime.index('- (void)tick:(CADisplayLink *)link {')
end = runtime.index('- (void)writeDiagnostic {', start)
tick = runtime[start:end]
for forbidden in ('CFPreferences', 'SBCPU120HzEnabled', 'writeToFile:', 'notify_post', 'snapshotView'):
    assert forbidden not in tick
assert runtime.count('writeToFile:') == 1
for field in ('generatedAt','pid','loaded','enabled','originalCapability','selectorABI','installedHooks','requestSelector','requestedHz','callbackHz','sampleSeconds','pauseReason'):
    assert '@"'+field+'"' in runtime
assert 'panel Hz or game FPS' in runtime
assert '[d[@"generatedAt"] doubleValue] < requestedAt' in prefs
rows = plistlib.loads((root/'sbcpuprefs/Resources/Root.plist').read_bytes())['items']
assert any(row.get('action') == 'show120HzDiagnostics' for row in rows)
assert 'SBCPURefreshRate_LDFLAGS += -L$(THEOS_VENDOR_LIBRARY_PATH)/iphone/roothide -lroothide' in makefile
assert 'CFGetTypeID(value) == CFBooleanGetTypeID()' in source
assert 'if (value) CFRelease(value);' in source
print('PASS MotionX public ABI, iOS availability, lifecycle, memory-only sampling, event prefs, diagnostic freshness and SpringBoard-only scope')
