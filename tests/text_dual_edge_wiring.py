from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
rows=plistlib.loads((r/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())['items']
c=(r/'sbcpuprefs/SBCPUTextOnlyController.m').read_text()
for key in ['floatingTextOnlyDualLine','floatingTextOnly2DualLine']:
    row,=[x for x in rows if x.get('key')==key]
    assert row['default'] is False and row['cell']=='PSSwitchCell'
    assert row['get']=='getPreferenceValue:' and row['set']=='setPreferenceValue:specifier:'
    assert row['defaults']=='com.yourname.sbcpufloating'
    assert f'getBoolPref(CFSTR("{key}"), NO)' in s
assert 'CFPreferencesSetValue' in c and 'CFPreferencesSynchronize' in c
assert 'notify_post("com.yourname.sbcpufloating.prefschanged")' in c
assert next(x for x in rows if x.get('key')=='floatingTextOnlyMode2')['default'] is False
second=s[s.index('@implementation SBCPURootViewController (SBCPUSecondTextHUD)'):s.index('static void applyTextOnlyMode(void) {')]
assert second.count('g=textOnlySecondGeometry()')==2
assert 'SBCPUTextAnchorOffsetsMatch' in second
assert '[saved[@"offsetX"] doubleValue]==floatingTextOnly2X' not in second
assert 'setFloatPref(CFSTR("floatingTextOnly2X"),floatingTextOnly2X)' in second
assert 'SBCPUTextCaptureAnchor' in second and 'SBCPUTextResolveAnchor' in second
assert 'textOnlyGeometryForView(cpuWindow.rootViewController.view, YES)' in s
assert 'textOnlyGeometryForView(floatingView.superview, NO)' in s
assert 'MAX(second?0:4, g.width-MAX(a.x,b.x))' in s
assert 'second?textOnly2DualLine:textOnlyDualLine,frames' in s
assert 'frames[i].height/1.4' in s
print('PASS 5.00 dual switches default OFF / persistence / independent geometry / precise saved anchor wiring')
