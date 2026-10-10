#!/usr/bin/env python3
"""Source + packaged wiring contract; not a device/UI simulation."""
from pathlib import Path
import argparse, plistlib
root=Path(__file__).resolve().parents[1]
s=(root/'Tweak.xm').read_text()
page=plistlib.loads((root/'sbcpuprefs/Resources/Advanced.plist').read_bytes())
row,=[r for r in page['items'] if r.get('key')=='dynamicIslandProtectionEnable']
assert row['cell']=='PSSwitchCell' and row['label']=='灵动岛保护' and row['default'] is True
assert row['get']=='getPreferenceValue:' and row['set']=='setPreferenceValue:specifier:'
assert row['defaults']=='com.yourname.sbcpufloating'
assert row['PostNotification']=='com.yourname.sbcpufloating.prefschanged'
assert any('胶囊避让灵动岛，纯文字始终允许拖到屏幕顶端，文字可能被摄像头/系统显示遮挡。'==r.get('footerText') for r in page['items'])
controller=(root/'sbcpuprefs/SBCPUFloatingAdvancedController.m').read_text()
for token in ('getPreferenceValue:', 'setPreferenceValue:', 'CFPreferencesCopyValue', 'CFPreferencesSetValue', 'CFPreferencesSynchronize', 'notify_post("com.yourname.sbcpufloating.prefschanged")'):
    assert token in controller,token
nav=plistlib.loads((root/'sbcpuprefs/Resources/Root.plist').read_bytes())
assert any(r.get('detail')=='SBCPUFloatingAdvancedController' and r.get('label')=='浮窗全部设置' for r in nav['items'])
assert 'dynamicIslandProtectionEnable = getBoolPref(CFSTR("dynamicIslandProtectionEnable"), YES)' in s
geom=s[s.index('static SBCPUTextGeometry textOnlyGeometry'):s.index('static SBCPUTextPoint textOnlyLogicalCenter')]
assert 'g.top = SBCPUFloatingProtectedTop(1, dynamicIslandProtectionEnable, 0);' in geom
assert 'g.left = MAX(4,' in geom and 'g.bottom = MAX(10,' in geom
assert 'g.top = MAX' not in geom
margin=s[s.index('static CGFloat floatingTopSafeMargin'):s.index('// 状态栏胶囊尺寸')]
assert 'SBCPUFloatingProtectedTop(floatingTextOnlyMode, dynamicIslandProtectionEnable,' in margin
assert 'halfH+floatingTextOnlyY,g.top+halfH' in s
assert 'p.y-self.bounds.size.height/2-2' not in s and 'halfH+2+floatingTextOnlyY' not in s
pan=s[s.index('- (void)handlePan:'):s.index('- (BOOL)gestureRecognizer:',s.index('- (void)handlePan:'))]
assert pan.index('if (floatingTextOnlyMode)')<pan.index('CGFloat minY =')
assert 'p.y,g.top+self.bounds.size.height/2' in pan
clamp=s[s.index('static void clampAndPositionFloatingView(CGPoint targetCenter, BOOL animate) {'):s.index('static void applyTextOnlyTextFilter(void) {')]
assert clamp.index('if (floatingTextOnlyMode)') < clamp.index('CGRect realFrame')
assert 'g.top+floatingView.bounds.size.height/2' in clamp
assert 'floatingView.center = textOnlyContainerCenter(p,g);' in clamp
locked=s[s.index('static CGPoint resolveLockedTextCenter'):s.index('static CGFloat floatingTopSafeMargin')]
assert 'g.left,g.top,g.right,g.bottom' in locked
hit=s[s.index('@implementation SBCPUWindow'):s.index('@implementation SBCPUValuePickerController')]
assert '[floatingView pointInside:p withEvent:event]' in hit and 'safeArea' not in hit
notify=s[s.index('static void onCCNotificationReceived'):s.index('static void registerV160Observers')]
assert 'LoadPreferences();' in notify and 'updateFloatingSize();' in notify
args=argparse.ArgumentParser(); args.add_argument('--staged',type=Path); opt=args.parse_args()
if opt.staged:
    bundle,=opt.staged.rglob('SBCPUPrefs.bundle')
    assert plistlib.loads((bundle/'Advanced.plist').read_bytes())==page
    info=plistlib.loads((bundle/'Info.plist').read_bytes())
    assert b'SBCPUFloatingAdvancedController' in (bundle/info['CFBundleExecutable']).read_bytes()
print('PASS protection switch navigation/persistence/notify and text drag/restore/lock/hit/packaged wiring')
