from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text(); c=(r/'sbcpuprefs/SBCPUTextOnlyController.m').read_text()
rows=plistlib.loads((r/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())['items']
keys=['floatingTextOnlyDataGap','floatingTextOnly2DataGap']
for key in keys:
 row,=[x for x in rows if x.get('key')==key]
 assert (row['min'],row['max'],row['default'])==(-15,12,4)
 assert row['cell']=='PSSliderCell' and row['showValue']
 assert row['get']=='getPreferenceValue:' and row['set']=='setPreferenceValue:specifier:'
 assert row['defaults']=='com.yourname.sbcpufloating'
 assert f'{key} = SBCPUTextDataGap(getFloatPref(CFSTR("{key}"), 4))' in s
 assert f'[key isEqualToString:@"{key}"]' in c
assert 'second?floatingTextOnly2DataGap:floatingTextOnlyDataGap,second && textOnly2NetworkDualLine,fpsWidth,frames' in s
assert 'CFPreferencesSetValue' in c and 'CFPreferencesSynchronize' in c
assert 'notify_post("com.yourname.sbcpufloating.prefschanged")' in c
assert 'if (floatingView) applyTextOnlyMode();' in s
assert 'kPrefChangedNotification' in s and 'onCCNotificationReceived' in s
sync=c[c.index('- (void)applyDataGapToSecond'):c.index('- (void)preset:')]
assert 'valueForKeyName:@"floatingTextOnlyDataGap" fallback:@4' in sync
assert '[self writeValues:@{@"floatingTextOnly2DataGap":@(gap)}]' in sync
assert '[self reloadSpecifiers]' in sync
assert any(x.get('action')=='applyDataGapToSecond' for x in rows)
assert all('LetterSpacing' not in x.get('key','') for x in rows)
assert 'NSKern' not in s+c+(r/'SBCPUTextOnlyTypography.h').read_text()
assert 'monospacedDigitSystemFontOfSize' in s
# Retain layout-only API: no values/digits/strings affect frames.
policy=(r/'SBCPUTextSlotPolicy.h').read_text()
assert 'double gap, SBCPUTextSlot slots[10]' in policy
assert 'x+gap' in policy and 'cells[metric] * font * .65;' in policy
print('PASS 4.99 independent defaults/range, one-shot copy, persistent notification + live layout, no character spacing')
