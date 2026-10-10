"""New uploaded 1.1 is investigated, never blindly executed or distributed."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
h = (root/'SBCPURefreshDynamic120Audit.h').read_text()
r = (root/'SBCPURefreshRuntime.h').read_text()
u = (root/'sbcpuprefs/SBCPUPrefsRootListController.m').read_text()
assert 'dlsym(RTLD_DEFAULT, "CADeviceDisableMinimumFrameDuration")' in h
assert 'dladdr(symbol, &info)' in h
for token in ('cABI', 'unknown:', 'not called', 'NOT CADynamicFrameRateSource', 'implementation', 'blocked;', 'RTLD_DEFAULT; local/shared-cache', 'UIStatusBarWindow', 'sourcePackageSHA256'):
    assert token in h, token
for forbidden in ('MSHookFunction(', 'MSHookMessageEx(', 'method_setImplementation(', 'dlopen(', 'dispatch_after(', 'scheduledTimer', 'addSubview:', 'objc_msgSend(', 'symbol(', '(*symbol)'):
    assert forbidden not in h, forbidden
assert r.count('SBCPURefreshDynamic120Audit()') == 1
assert 'SBCPURefreshDynamic120Audit()' not in r[:r.index('- (void)writeDiagnostic {')]
assert 'dynamic120Investigation' in r and 'dynamic120Investigation' in u
assert '未移植私有hook，不是120生效证据' in u
assert not list(root.rglob('0fix120hz.dylib'))
print('PASS dynamic120: manual read-only symbol/ObjC ABI evidence; no private invocation, hook, hidden view or original binary')
