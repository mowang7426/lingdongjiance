from pathlib import Path
root = Path(__file__).resolve().parents[1]
s = (root/'Tweak.xm').read_text()
center = s[s.index('- (void)setCenter:'):s.index('- (void)handleDoubleTap:')]
assert center.index('floatingTextOnlyMode && lockedTextAnchorValid') < center.index('center = self.lockedCenter')
assert 'SBCPULockedCoordinate' in center
for token in ('SBCPU.LockedTextAnchor','captureLockedTextAnchor(anchor)', 'saveLockedTextAnchor()',
              'textOnlyLogicalCenter(self.center,g)', 'textOnlyContainerCenter(p,g)',
              'g.bounds.size.width < g.bounds.size.height && UIInterfaceOrientationIsLandscape(o)',
              'viewSafeAreaInsetsDidChange', 'final scene/container/safe area',
              'Legacy centers are migrated only after text bounds/rotation exist',
              'Do not clamp logical text a second time'):
    assert token in s, token
layout = s[s.index('static void updateFloatingSize(void) {'):s.index('static void createCPUWindow(void) {')]
assert layout.index('if (floatingView.positionLocked) {') < layout.index('CGFloat x = SBCPUTextOnlyAnchorX')
assert 'int r = textOnlyGeometry().rotation;' in layout
assert 'lockedTextAnchorValid = [textAnchor[@"version"] isKindOfClass:NSNumber.class]' in s
assert '[textAnchor[@"version"] integerValue] == 1' in s
pan = s[s.index('- (void)handlePan:'):s.index('- (BOOL)gestureRecognizer:',s.index('- (void)handlePan:'))]
assert 'floatingTextOnlyX + translation.x' not in pan
assert 'SBCPUTextSafeCoordinate' in pan and 'else if (rememberPositionEnable)' in pan
print('PASS text logical orientation/capture/restore/unlock/drag wiring; capsule legacy gate retained')
