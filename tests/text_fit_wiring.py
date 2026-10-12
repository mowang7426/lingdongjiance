from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
start=s.index('static void applyTextOnlyMode(void) {')
end=s.index('static void handleTextOnlyModeTransition',start)
a=s[start:end]
for required in ['layoutTextSlots(textOnlyLabel,NO,textGeometry)',
                 'SBCPUTextResolveAnchor(lockedTextAnchor',
                 'SBCPUTextSafeCoordinate(p.x', 'SBCPUTextSafeCoordinate(p.y',
                 'textOnlyContainerCenter(p,textGeometry)']:
    assert required in a, required
helper=s[s.index('static CGSize layoutTextSlots'):s.index('static void applyTextOnlyTextFilter(void) {')]
for required in ['SBCPUTextSlotsLayout(mask,fs,available,frames)', 'monospacedDigitSystemFontOfSize:fs',
                 'slot.adjustsFontSizeToFitWidth=NO', 'slot.numberOfLines=1', 'slot.clipsToBounds=YES']:
    assert required in helper, required
for forbidden in ['NSTimer','CADisplayLink','NSLineBreakByTruncating','minimumScaleFactor', 'sizeThatFits', 'boundingRect']:
    assert forbidden not in a+helper, forbidden
assert 'componentsJoinedByString:@" "' in (r/'SBCPUTextOnlyFormat.h').read_text()
assert 'SBCPUTextOnlyMinimumScale' not in s
# The production alpha mask delegates glyph rendering to the same UILabel,
# so wrapping/fitted typography applies to fixed and realtime-invert modes.
b=(r/'SBCPUTextBackdropLabel.m').read_text()
assert '[self.glyphLabel drawTextInRect:self.bounds]' in b
print('PASS: production compact/fitted/wrapped layout, drag/lock clamp and mask rendering wiring (not UIKit device simulation)')
