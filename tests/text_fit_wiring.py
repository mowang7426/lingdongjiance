from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
start=s.index('static void applyTextOnlyMode(void) {')
end=s.index('static void handleTextOnlyModeTransition',start)
a=s[start:end]
for required in ['textGeometry.width-textGeometry.left-textGeometry.right',
                 'SBCPUTextOnlyFitFont(naturalWidth, available, floatingTextOnlyFontSize)',
                 'textOnlyLabel.numberOfLines = wrap ? 0 : 1',
                 'NSLineBreakByWordWrapping', 'adjustsFontSizeToFitWidth = NO',
                 'sizeThatFits:CGSizeMake(rowWidth, CGFLOAT_MAX)',
                 'MIN(available, fittedWidth + 2)', 'MIN(maxHeight,',
                 'SBCPUTextResolveAnchor(lockedTextAnchor',
                 'SBCPUTextSafeCoordinate(p.x', 'SBCPUTextSafeCoordinate(p.y',
                 'textOnlyContainerCenter(p,textGeometry)']:
    assert required in a, required
for forbidden in ['NSTimer','CADisplayLink','NSLineBreakByTruncating','NSLineBreakByClipping','minimumScaleFactor']:
    assert forbidden not in a, forbidden
assert 'componentsJoinedByString:@" "' in (r/'SBCPUTextOnlyFormat.h').read_text()
assert 'SBCPUTextOnlyMinimumScale' not in s
# The production alpha mask delegates glyph rendering to the same UILabel,
# so wrapping/fitted typography applies to fixed and realtime-invert modes.
b=(r/'SBCPUTextBackdropLabel.m').read_text()
assert '[self.glyphLabel drawTextInRect:self.bounds]' in b
print('PASS: production compact/fitted/wrapped layout, drag/lock clamp and mask rendering wiring (not UIKit device simulation)')
