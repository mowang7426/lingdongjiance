"""Read-only investigation must not become a guessed private ABI intervention."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
runtime = (root/'SBCPURefreshRuntime.h').read_text()
ui = (root/'sbcpuprefs/SBCPUPrefsRootListController.m').read_text()
for token in ('objectForInfoDictionaryKey:@"CADisableMinimumFrameDurationOnPhone"',
              'CADynamicFrameRateSource.', 'setHighFrameRateReasons:count:',
              'CADisplay.setHighFrameRateReason: (not called)', 'hostBundle',
              'phoneHighFrameRateGate', 'limitation', 'sampleFresh', 'sampleAgeSeconds',
              'CACurrentMediaTime()-_sampleAt <= 5', 'lowPowerMode', 'thermalState'):
    assert token in runtime, token
for forbidden in ('MSHookMessageEx', 'MSHookFunction', 'method_setImplementation', 'dlsym(',
                  'setHighFrameRateReasons:count:]', 'setHighFrameRateReason:1'):
    assert forbidden not in runtime, forbidden
assert 'phoneHighFrameRateGate' in ui and 'limitation' in ui
assert 'UIScreen.mainScreen.maximumFramesPerSecond' in runtime
assert 'no UIScreen/private getter spoofing' in runtime
# Per-callback path remains memory-only.
tick = runtime[runtime.index('- (void)tick:(CADisplayLink *)link {'):runtime.index('- (void)writeDiagnostic {')]
for forbidden in ('writeToFile', 'synchronize', 'notify_post', 'NSUserDefaults', 'dispatch_after'):
    assert forbidden not in tick, forbidden
print('PASS refresh limitations: read-only gate/ABI discovery, fresh samples, no private invocation or per-frame IO')
