#!/usr/bin/env python3
"""Host-executed production state policy + source isolation guards, not iOS rendering."""
from pathlib import Path
import os, re, subprocess, tempfile, plistlib
root = Path(__file__).resolve().parents[1]
tweak = (root / 'Tweak.xm').read_text()
source = (root / 'SBCPUTextBackdropLabel.m').read_text()
names = 'cpuTitle cpuValue cpuFreq fpsTitle fpsValue fpsSub batteryValue batterySub tempValue tempSub currentValue currentSub time signal miniCpu miniFps miniBatt miniTemp miniDockInfo'.split()
allocated = re.findall(r'_(\w+)Label = \[\[SBCPUCapsuleBackdropLabel alloc\]', tweak)
assert set(allocated) == set(names) and len(allocated) == 19
start = tweak.index('- (void)applyCapsuleTextFilter {')
method = tweak[start:tweak.index('- (void)layoutSubviews', start)]
assert set(re.findall(r'_(\w+)Label', method)) == set(names)
for token in ('SBCPUCapsuleTextEnabled', 'parent.hidden', 'group == folded', 'label.text.length > 0'):
    assert token in method
for token in ('layer.filters', 'compositingFilter', 'snapshotView', 'NSTimer', 'frame =', 'cornerRadius', 'textColor ='):
    assert token not in method
assert '[floatingView applyCapsuleTextFilter]; // preference changes' in tweak
assert 'applyTextOnlyMode(void) {\n    [floatingView applyCapsuleTextFilter]' in tweak
for state in ('YES', 'NO'):
    assert f'_isCollapsed = {state};\n    [self applyCapsuleTextFilter];' in tweak
assert '- (void)applyAdaptiveTextColors {\n    [self applyCapsuleTextFilter];' in tweak
for prop in ('font', 'textAlignment', 'numberOfLines', 'lineBreakMode', 'adjustsFontSizeToFitWidth',
             'minimumScaleFactor', 'baselineAdjustment', 'semanticContentAttribute'):
    assert f'glyph.{prop} =' in source
assert '[self.glyphLabel drawTextInRect:self.bounds]' in source
assert 'if (hidden) self.realtimeInvertEnabled = NO' in source
assert 'if (!self.window) self.realtimeInvertEnabled = NO' in source
for token in ('snapshotView', 'renderInContext:', 'drawViewHierarchy', 'NSTimer', 'CADisplayLink', '%hook'):
    assert token not in source
assert source.count('_backdrop.filters = filters') == 1
assert 'if (!_backdrop && ![self createBackdrop]) return' in source
assert 'if (!_backdrop) [super drawTextInRect:rect]' in source
with (root / 'sbcpuprefs/Resources/TextOnly.plist').open('rb') as f:
    prefs = plistlib.load(f)
assert '实时反色适用于纯文字和胶囊' in str(prefs)
assert '其余颜色设置仍仅影响纯文字浮窗' in str(prefs)
program = r'''
#include <assert.h>
#include "SBCPUCapsuleTextPolicy.h"
int main(void) {
  for (int mode=-1; mode<=5; ++mode)
  for (int bits=0; bits<128; ++bits) {
    int textOnly=bits&1, notification=bits&2, startup=bits&4;
    int collapsed=bits&8, folded=bits&16, visible=bits&32, text=bits&64;
    int expected=mode==4 && !textOnly && !notification && !startup &&
        (!!collapsed==!!folded) && visible && text;
    assert(SBCPUCapsuleTextEnabled(mode,textOnly,notification,startup,collapsed,folded,visible,text)==!!expected);
  }
  /* Live transitions: normal -> fold -> text-only -> normal -> custom. */
  assert(SBCPUCapsuleTextEnabled(4,0,0,0,0,0,1,1));
  assert(!SBCPUCapsuleTextEnabled(4,0,0,0,1,0,1,1));
  assert(SBCPUCapsuleTextEnabled(4,0,0,0,1,1,1,1));
  assert(!SBCPUCapsuleTextEnabled(4,1,0,0,1,1,1,1));
  assert(SBCPUCapsuleTextEnabled(4,0,0,0,0,0,1,1));
  assert(!SBCPUCapsuleTextEnabled(3,0,0,0,0,0,1,1));
  return 0;
}
'''
with tempfile.TemporaryDirectory() as d:
    path = Path(d)
    (path/'policy.c').write_text(program)
    subprocess.run([os.environ.get('CC','cc'), '-std=c11', '-Wall', '-Wextra', '-Werror',
                    '-I'+str(root), str(path/'policy.c'), '-o', str(path/'policy')], check=True)
    subprocess.run([str(path/'policy')], check=True)
print('PASS: 896 production state combinations, transitions, 19-label isolation, UIKit mask typography, fallback/cache guards')
