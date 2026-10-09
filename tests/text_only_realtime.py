#!/usr/bin/env python3
"""Host color-policy execution + wiring guards; NOT an iOS compositor test."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SBCPUTextBackdropLabel.m').read_text()
header = (root / 'SBCPUTextBackdropLabel.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
make = (root / 'Makefile').read_text()
policy = (root / 'SBCPUTextOnlyColor.h').read_text()
mode = tweak[tweak.index('static void applyTextOnlyTextFilter(void) {'):tweak.index('static void updateFloatingSize(void) {')]
assert ': UILabel' in header and ': CATextLayer' in source
assert 'NSClassFromString(@"CABackdropLayer")' in source
assert 'NSClassFromString(@"CAFilter")' in source
assert '@[@"gaussianBlur", @"colorBrightness", @"colorContrast", @"colorSaturate", @"colorInvert"]' in source
assert '@[@50.0, @(-0.285), @1000.0, @0.0]' in source
for token in ('inputRadius', 'inputAmount', 'inputNormalizeEdges', 'respondsToSelector:',
              'isSubclassOfClass:CALayer.class', '@catch', '@finally', 'SBCPUBackdropUnavailable = YES',
              'if (SBCPUBackdropUnavailable) return NO', '_backdrop.filters = filters',
              '_backdrop.mask = _alphaMask', 'NSForegroundColorAttributeName:UIColor.whiteColor',
              'CTLineGetTypographicBounds', 'CTLineDraw', 'ascent - descent',
              'width / width', 'setDisableActions:YES', '[super layoutSubviews]',
              '[_lastText isEqualToString:self.text]', '[_lastFont isEqual:self.font]',
              'CGRectEqualToRect(_lastBounds, self.bounds)', '_lastScale == scale'):
    assert token in source, token
for token in ('differenceBlendMode', 'snapshotView', 'drawViewHierarchy', 'renderInContext:',
              'sampleBackgroundLuminance', 'CADisplayLink', 'NSTimer', '%hook', 'UIGraphicsImageRenderer'):
    assert token not in source + mode, token
assert 'self.textColor =' not in source  # fallback never becomes clear
assert 'if (!_backdrop) [super drawTextInRect:rect]' in source
setter = source[source.index('- (void)setRealtimeInvertEnabled:'):source.index('- (void)setText:')]
assert '[self syncBackdrop]' in setter
sync = source[source.index('- (void)syncBackdrop'):source.index('- (void)setRealtimeInvertEnabled:')]
assert sync.index('CGRectEqualToRect') < sync.index('[self createBackdrop]')
assert 'if (!_backdrop && ![self createBackdrop]) return' in sync
assert 'if (!_realtimeInvertEnabled || self.text.length == 0)' in sync
clear = source[source.index('- (void)clearBackdrop'):source.index('- (BOOL)createBackdrop')]
for token in ('removeFromSuperlayer', '_backdrop.mask = nil', '_backdrop.filters = nil',
              '_backdrop = nil', '_alphaMask = nil', '_lastText = nil', '_lastFont = nil'):
    assert token in clear
assert '[[SBCPUTextBackdropLabel alloc] initWithFrame:CGRectZero]' in mode
assert '[floatingView addSubview:textOnlyLabel]' in mode
assert 'view.hidden = (view != textOnlyLabel)' in mode
assert 'floatingTextOnlyColor == 4 && textOnlyLabel.text.length > 0' in mode
assert 'textOnlyLabel.realtimeInvertEnabled = NO' in mode
assert 'SBCPUFloating_FILES = Tweak.xm SBCPUTextBackdropLabel.m' in make
assert 'CoreGraphics CoreText' in make and 'QuartzCore' in make
assert 'LICENSE.TrollSpeed' in make and 'TEXT_ONLY_MODE.md' in make
license_text = (root / 'LICENSE.TrollSpeed').read_text()
assert 'Copyright (c) 2023 Lessica' in license_text and 'MIT License' in license_text
assert 'a609be260c8261ead36509c3bc4ded8479da9c40' in (root / 'TEXT_ONLY_MODE.md').read_text()

# Execute actual production C-compatible functions, not a Python reimplementation.
functions = '\n'.join(re.findall(r'static inline int SBCPUText(?:SystemStyle|ColorMode|UsesWhite)\([^}]+\}', policy))
assert functions.count('static inline int') == 3
program = '#include <assert.h>\n#include <limits.h>\n' + functions + r'''
int main(void) {
    for (int mode = 0; mode <= 4; mode++) assert(SBCPUTextColorMode(mode) == mode);
    assert(SBCPUTextColorMode(-1) == 0 && SBCPUTextColorMode(5) == 0);
    assert(SBCPUTextColorMode(INT_MIN) == 0 && SBCPUTextColorMode(INT_MAX) == 0);
    assert(SBCPUTextColorMode(LLONG_MIN) == 0 && SBCPUTextColorMode(LLONG_MAX) == 0);
    assert(SBCPUTextColorMode(4294967300LL) == 0);
    for (int screen = -1; screen <= 3; screen++) {
        for (int window = -1; window <= 3; window++) {
            int style = SBCPUTextSystemStyle(screen, window);
            assert(style == ((screen == 1 || screen == 2) ? screen : (window == 2 ? 2 : 1)));
            assert(SBCPUTextUsesWhite(0, style) == (style == 2));
            assert(SBCPUTextUsesWhite(4, style) == SBCPUTextUsesWhite(0, style));
            assert(SBCPUTextUsesWhite(1, style));
            assert(!SBCPUTextUsesWhite(2, style));
            assert(!SBCPUTextUsesWhite(3, style));
            assert(SBCPUTextUsesWhite(99, style) == SBCPUTextUsesWhite(0, style));
        }
    }
    return 0;
}
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'colors.c').write_text(program)
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-Wall', '-Wextra', '-Werror',
                    str(path / 'colors.c'), '-o', str(path / 'colors')], check=True)
    subprocess.run([str(path / 'colors')], check=True)
print('PASS: realtime backdrop wiring, lifecycle, no screenshot/timer, MIT, production color policy')
