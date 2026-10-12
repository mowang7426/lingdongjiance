from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1];s=(r/'Tweak.xm').read_text()
layout=s[s.index('static CGSize layoutTextSlots'):s.index('static void applyTextOnlyTextFilter(void) {')]
assert layout.index('SBCPUTextSlotsLayoutNetwork(mask,fs,available,second?floatingTextOnly2DataGap:floatingTextOnlyDataGap,second && textOnly2NetworkDualLine,frames)') < layout.index('NSString *value=')
for token in ['slot.adjustsFontSizeToFitWidth=NO','slot.numberOfLines=1','slot.frame=CGRectMake(frames[i].x',
              'slot.font=slotFont','SBCPUTextOnlyAttributedRow','textNetworkDownloadRate,textNetworkUploadRate,i==8,i==9']:
    assert token in layout+s,token
for forbidden in ['sizeThatFits','boundingRect','minimumScaleFactor','NSTimer','CADisplayLink']:
    assert forbidden not in layout
assert 'layoutTextSlots(textOnlyLabel,NO,textGeometry)' in s
assert 'layoutTextSlots(textOnly2Label,YES,g)' in s
assert s.count('    sampleTextNetwork();')==1
assert 'floatingTextOnlyMode2 && secondVisible ? textSlotMask(YES) : 0' in s
clear=s[s.index('static void clearTextSlots'):s.index('static UIColor *textSlotColor')]
assert clear.index('slot.realtimeInvertEnabled = NO') < clear.index('[slot removeFromSuperview]')
second=s[s.index('static void updateTextOnlySecond(void) {'):s.index('static void applyTextOnlyMode(void) {')]
assert '!SBCPUTextHUDShouldExist(isEnabled,floatingTextOnlyMode2,cpuWindow!=nil,cpuWindow.rootViewController!=nil)' in second
assert 'clearTextSlots(textOnly2Label); [textOnly2Label removeFromSuperview]; textOnly2Label=nil' in second
assert 'textOnly2Label.userInteractionEnabled=!textOnly2Locked' in second
assert 'textOnly2Label.hidden=textOnly2Label.hidden || floatingView.hidden' in second
assert 'SBCPUTextResolveAnchor(anchor,g.width,g.height' in second
assert 'textOnlyContainerCenter(p,g)' in second
hit=s[s.index('@implementation SBCPUWindow'):s.index('@implementation SBCPUValuePickerController')]
assert '!textOnly2Locked' in hit and 'return textOnly2Label' in hit and 'return nil;' in hit
for suffix in ['CPU','Frequency','FPS','Battery','Temperature','Current','SIM1','SIM2','UploadNetwork','DownloadNetwork']:
    rows=plistlib.loads((r/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())['items']
    row,=[x for x in rows if x.get('key')=='floatingTextOnly2Show'+suffix]
    assert row['defaults']=='com.yourname.sbcpufloating'
assert next(x for x in rows if x.get('key')=='floatingTextOnlyMode2')['default'] is False
print('PASS dual HUD fixed independent slots, shared sample, directions, controls, anchor/hit-test/close cleanup wiring')
