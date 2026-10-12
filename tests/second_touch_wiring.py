from pathlib import Path
import plistlib
import subprocess
r = Path(__file__).resolve().parents[1]
s = (r/'Tweak.xm').read_text()
base = subprocess.check_output(['git','show','281bc6adeadcfebf1c2a2cbd56845f8a66d9031e:Tweak.xm'],cwd=r,text=True)
second = s[s.index('@implementation SBCPUSecondTextWindow'):s.index('@implementation SBCPUValuePickerController')]
assert '- (BOOL)_ignoresHitTest' in second
assert '- (BOOL)pointInside:' in second and 'if ([self _ignoresHitTest]) return NO;' in second
assert 'if (![self pointInside:point withEvent:event]) return nil;' in second
assert 'return textOnly2Label;' in second and '[super hitTest:' not in second
assert 'SBCPUSecondTouchIgnored(textOnly2Locked' in second
update = s[s.index('static void updateTextOnlySecond(void) {'):s.index('static void applyTextOnlyMode(void) {')]
assert 'UIView *host=textOnly2Window.rootViewController.view;' in update
assert 'textOnly2Window.userInteractionEnabled=!textOnly2Locked;' in update
assert 'gesture.enabled=!textOnly2Locked' in update
assert 'textOnly2Window.hidden=cpuWindow.hidden || textOnly2Label.hidden;' in update
assert 'textOnly2Window.windowScene=cpuWindow.windowScene;' in update
assert 'makeKey' not in update
assert 'cpuWindow.userInteractionEnabled' not in s
primary = s[s.index('@implementation SBCPUWindow'):s.index('@implementation SBCPUSecondTextWindow')]
old_primary = base[base.index('@implementation SBCPUWindow'):base.index('@implementation SBCPUValuePickerController')]
removed = '''    if (textOnly2Label && !textOnly2Label.hidden && !textOnly2Locked && textOnly2Label.alpha > 0.01) {
        CGPoint p=[self convertPoint:point toView:textOnly2Label];
        if ([textOnly2Label pointInside:p withEvent:event]) return textOnly2Label;
    }
'''
assert primary.rstrip() == old_primary.replace(removed,'').rstrip()
# Window 1 implementation and all sampling/control logic remain byte-identical.
for start,end in [('@implementation SBCPUFloatingView','@implementation SBCPUSecondTextWindow'),]:
    # Restrict to the FloatingView implementation, before following classes.
    a = s.index(start); b = base.index(start)
    assert s[a:s.index('\n@end',a)+5] == base[b:base.index('\n@end',b)+5]
load = s[s.index('static void LoadPreferences(void) {'):s.index('static void SavePreferencesAndNotify(void) {')]
assert 'getBoolPref(CFSTR("floatingTextOnly2Locked"), NO)' in load
assert 'if (floatingView) applyTextOnlyMode();' in load
controller = (r/'sbcpuprefs/SBCPUTextOnlyController.m').read_text()
assert 'CFPreferencesSynchronize' in controller and 'notify_post("com.yourname.sbcpufloating.prefschanged")' in controller
rows = plistlib.loads((r/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())['items']
assert len([row for row in rows if row.get('key')=='floatingTextOnly2Locked']) == 1
assert next(row for row in rows if row.get('key')=='floatingTextOnly2NetworkDualLine')['default'] is False
assert s.count('scheduledTimer') == base.count('scheduledTimer')
print('PASS independent window2 / whole-window rejection / cancellation / immediate preferences / unchanged window1 / no new timer')
