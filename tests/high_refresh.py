#!/usr/bin/env python3
"""Host policy execution + source/resource/build-wiring contracts; NOT an iOS build."""
from pathlib import Path
import plistlib, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
def text(name): return (ROOT/name).read_text()
with tempfile.TemporaryDirectory() as tmp:
    binary = str(Path(tmp)/'policy')
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-pedantic',str(ROOT/'tests/high_refresh_policy.c'),'-lm','-o',binary],check=True)
    subprocess.run([binary],check=True)
    # Exercise real project Makefile parsing for each scheme using stub Theos
    # includes. Validates variable wiring only, not SDK compilation/DEB staging.
    makepath = Path(tmp)/'makefiles'; makepath.mkdir()
    for name in ['common','tweak','tool','bundle','aggregate']:
        (makepath/(name+'.mk')).write_text('')
    probe = Path(tmp)/'probe.mk'
    probe.write_text('include '+str(ROOT/'Makefile')+'\n.PHONY: contract\ncontract:\n\t@test "$(SBCPUHighRefresh_FILES)" = "SBCPUHighRefresh.m"\n\t@test "$(SBCPUHighRefresh_LIBRARIES)" = "substrate"\n\t@test "$(SBCPUHighRefresh_INSTALL_TARGET_PROCESSES)" = "SpringBoard"\n\t@test "$(filter SBCPUHighRefresh,$(TWEAK_NAME))" = "SBCPUHighRefresh"\n')
    for scheme in ['rootless','roothide']:
        subprocess.run(['make','--no-print-directory','-f',str(probe),'contract',f'THEOS={tmp}',f'THEOS_MAKE_PATH={makepath}',f'THEOS_PACKAGE_SCHEME={scheme}'],check=True,cwd=ROOT)
        print(scheme, 'Makefile wiring passed (stub includes, not package build)')
rows = plistlib.loads((ROOT/'sbcpuprefs/Resources/Root.plist').read_bytes())['items']
row, = [r for r in rows if r.get('key')=='springBoard120HzEnabled']
assert row['default'] is False and row['cell']=='PSSwitchCell'
assert row['defaults']=='com.yourname.sbcpufloating.highrefresh'
assert row['get']=='getPreferenceValue:' and row['set']=='setPreferenceValue:specifier:'
footer = '\n'.join(r.get('footerText','') for r in rows)
for phrase in ['不是全 App 120 帧','耗电','手动注销','不会自动注销','≥120Hz']: assert phrase in footer
assert plistlib.loads((ROOT/'SBCPUHighRefresh.plist').read_bytes()) == {'Filter':{'Bundles':['com.apple.springboard']}}
prefs = text('SBCPUHighRefreshPreferences.h'); runtime = text('SBCPUHighRefresh.m'); ui = text('sbcpuprefs/SBCPUPrefsRootListController.m')
for fragment in ['CFBooleanGetTypeID()', 'CFPreferencesSynchronize', 'CFPreferencesCopyValue', 'springBoard120HzEnabled', row['defaults']]: assert fragment in prefs
assert 'if (SBHRWriteEnabled([value boolValue])) notify_post(SBHR_NOTIFY);' in ui
assert 'return @(SBHRReadEnabled())' in ui
for fragment in ['notify_register_dispatch(SBHR_NOTIFY', 'atomic_store_explicit', 'atomic_load_explicit', 'dispatch_once(&once', 'original(screen, maximum) < 120', '@"SpringBoard"', '@"com.apple.springboard"', 'method_getNumberOfArguments', 'method_copyReturnType', 'method_copyArgumentType', 'SBHRABI(', '@encode(CAFrameRateRange)', '@encode(NSInteger)']:
    assert fragment in runtime, fragment
for forbidden in ['NSTimer', 'dispatch_source_create', 'thermalState', 'notify_post(', 'system(', 'posix_spawn', 'kill(']: assert forbidden not in runtime
assert runtime.index('original(screen, maximum) < 120') < runtime.index('Install(screenClass, maximum')
for original in ['gScreenOriginal','gPolicyOriginal','gControllerOriginal','gFPSOriginal','gRangeOriginal']: assert original+'(object, selector' in runtime
assert 'SBCPUHighRefresh.m' not in text('sbcpuprefs/Makefile')
print('settings/notification/filter/runtime ABI contracts passed')
