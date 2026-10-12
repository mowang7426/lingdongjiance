from pathlib import Path
import plistlib, subprocess, sys
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
base=subprocess.check_output(['git','show','281bc6adeadcfebf1c2a2cbd56845f8a66d9031e:Tweak.xm'],cwd=r,text=True)
def between(a,b): return s[s.index(a):s.index(b,s.index(a))]
update=between('static void updateTextOnlySecond(void) {','static void applyTextOnlyMode(void) {')
primary=between('@implementation SBCPUWindow','@implementation SBCPUValuePickerController')
assert 'SBCPUSecondTextWindow' not in s and 'textOnly2Window' not in s
assert '_ignoresHitTest' not in s
assert 'UIView *host=cpuWindow.rootViewController.view;' in update
assert 'initWithTarget:cpuWindow.rootViewController action:@selector(sbcpu_secondTextPan:)' in update
assert '[textOnly2Label addGestureRecognizer:pan]; [host addSubview:textOnly2Label];' in update
assert 'syncSecondTextInteraction();' in update
sync=between('static void syncSecondTextInteraction(void)', '@implementation SBCPURootViewController (SBCPUSecondTextHUD)')
assert 'gesture.enabled=!textOnly2Locked' in sync and 'textOnly2Label.userInteractionEnabled=!textOnly2Locked' in sync
assert 'if (textOnly2Locked) textOnly2Dragging=NO;' in sync
assert 'textOnly2Label.window==self' in primary
assert primary.index('return textOnly2Label;') < primary.index('return floatingView;')
assert 'settingsShowing' not in sync+update and 'detailShowing' not in sync+update
assert 'cpuWindow.userInteractionEnabled' not in s
pan=between('- (void)sbcpu_secondTextPan:', '\n@end')
assert 'UIView *host=textOnly2Label.superview;' in pan and 'translationInView:host' in pan
assert 'pan.view!=textOnly2Label || textOnly2Label.window!=cpuWindow' in pan
# Preserve the production anchor capture/end implementation, not merely formulas.
end='    if (pan.state==UIGestureRecognizerStateEnded'
oldpan=base[base.index('- (void)sbcpu_secondTextPan:'):base.index('\n@end',base.index('- (void)sbcpu_secondTextPan:'))]
assert pan[pan.index(end):]==oldpan[oldpan.index(end):]
a=s.index('@implementation SBCPUFloatingView'); b=base.index('@implementation SBCPUFloatingView')
assert s[a:s.index('\n@end',a)+5]==base[b:base.index('\n@end',b)+5]
assert s.count('scheduledTimer')==base.count('scheduledTimer')
rows=plistlib.loads((r/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())['items']
assert len([v for v in rows if v.get('key')=='floatingTextOnly2Locked'])==1
assert next(v for v in rows if v.get('key')=='floatingTextOnly2NetworkDualLine')['default'] is False
assert 'getBoolPref(CFSTR("floatingTextOnly2Locked"), NO)' in s
print('PASS actual host/target/coordinates/lock restore wiring; unchanged window1 and drag anchors')
if '--emit-native' in sys.argv:
    # Execute production method bodies against an Objective-C event-tree double.
    # The layout tail remains covered by existing anchor/layout regressions.
    prefix=update[update.index('    if (!SBCPUTextHUDShouldExist'):update.index('    SBCPUTextGeometry g=textOnlySecondGeometry();')]
    panprefix=pan[:pan.index(end)].replace('SBCPUTextGeometry g=textOnlySecondGeometry();','SBCPUTextGeometry g=textOnlySecondGeometry(); (void)g;')+'}\n'
    template=(r/'tests/second_touch_event_tree.m.in').read_text()
    template=template.replace('/*SYNC*/',sync).replace('/*UPDATE*/','static void updateTextOnlySecond(void) {\n'+prefix+'}\n').replace('/*PAN*/',panprefix).replace('/*WINDOW*/',primary)
    Path(sys.argv[sys.argv.index('--emit-native')+1]).write_text(template)
