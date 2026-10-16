from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
layout=s[s.index('static CGSize layoutTextSlots'):s.index('static void applyTextOnlyTextFilter(void) {')]
assert layout.index('SBCPUTextFPSConfiguredWidth(font)') < layout.index('NSString *value=')
assert 'SBCPUTextSlotsLayoutNetworkFPS(mask,fs,available,second?floatingTextOnly2DataGap:floatingTextOnlyDataGap,second && textOnly2NetworkDualLine,fpsWidth,frames)' in layout
assert 'slot.font=slotFont' in layout and 'slot.adjustsFontSizeToFitWidth=NO' in layout
assert 'slot.lineBreakMode=NSLineBreakByClipping' in layout
assert 'slot.clipsToBounds=YES' in layout
budget=(r/'SBCPUTextFPSBudget.h').read_text()
for token in ['NSCache<UIFont *,NSNumber *>','[cache objectForKey:font]','n<1000','CTLineGetTypographicBounds','kCTLineBoundsUseGlyphPathBounds','ceil(extent)+2']:
    assert token in budget,token
for forbidden in ['fpsValueLabel','sampleTextNetwork','minimumScaleFactor','fontWithSize:']:
    assert forbidden not in budget,forbidden
assert s.count('SBCPUTextFPSConfiguredWidth(font)')==1
print('PASS font-keyed configuration budget shared by both text HUDs; no sampled value or shrinking')
