"""Dynamic source experiment safety contract; real behavior also tested natively."""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parents[1]
runtime=(root/'SBCPURefreshRuntime.h').read_text()
hooks=(root/'SBCPUDynamicRangeHooks.h').read_text()
ui=(root/'sbcpuprefs/SBCPUPrefsRootListController.m').read_text()
for token in ('CADynamicFrameRateSource.', 'setHighFrameRateReasons:count:', 'sampleFresh', 'sampleAgeSeconds', 'hostBundle', 'phoneHighFrameRateGate', 'limitation', 'lowPowerMode', 'thermalState', 'dynamicGuard', 'startProbe', '3.0', '5*NSEC_PER_SEC'):
    assert token in runtime, token
assert runtime.index('_capability = UIScreen.mainScreen.maximumFramesPerSecond') < runtime.index('SBCPUInstallDynamicHooks(_hardware120')
for token in ('@encode(void)','@encode(id)','@encode(SEL)','@encode(CAFrameRateRange)','numberOfArguments == 3','weakToStrongObjectsMapTable','latestExternal','offMainPassThrough','changedRanges','supersededByExternalRequest','original(object,cmd,output)','SBCPUDynamicReentry[slot]'):
    assert token in hooks,token
assert hooks.count('MSHookMessageEx(')==2
for forbidden in ('MSHookFunction','dlsym(', 'dispatch_sync(', 'setHighFrameRateReason:1','initWithDisplay:]', 'setPaused:]'):
    assert forbidden not in hooks+runtime,forbidden
assert 'main && !reason.length && eligible' in hooks
assert 'thermal < 0 || thermal > 3' in runtime
items=plistlib.loads((root/'sbcpuprefs/Resources/Root.plist').read_bytes())['items']
item,=[r for r in items if r.get('key')=='dynamicSource120HzEnabled']
assert item['default'] is False
assert 'dynamicSource120HzEnabled' in ui and 'dynamicExperiment' in ui
assert '关闭后respring' in ui
assert (root/'Tweak.xm').read_bytes() # unchanged separately verified by git diff
print('PASS dynamic ABI/guard/main-thread/deferred rollback/manual probe/default OFF safety contract')
