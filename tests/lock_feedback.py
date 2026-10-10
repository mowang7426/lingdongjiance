"""Source-contract tests; UIKit gesture execution remains a device acceptance test."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
s = (root / 'Tweak.xm').read_text()
def body(start, end):
    a = s.index(start)
    return s[a:s.index(end, a)]
toast = body('- (void)showLockFeedback:(NSString *)message {', '- (void)handleDoubleTap:')
assert '[host addSubview:toast]' in toast
assert 'toast.userInteractionEnabled = NO' in toast
assert 'dispatch_after(' in toast and '[toast removeFromSuperview]' in toast
assert 'NSTimer' not in toast and 'self.bounds =' not in toast and 'self.center =' not in toast
assert 'self.lockFeedbackLabel == toast' in toast  # old removal cannot clear newer feedback
lock = body('- (void)handleDoubleTap:', '- (BOOL)gestureRecognizerShouldBegin:')
for token in ('BOOL saved = [defaults synchronize]', '[defaults boolForKey:@"SBCPU.PositionLocked"]',
              'storedLocked != requestedLocked', '!centerMatches', '!textAnchorMatches',
              'previousAnchorValid', 'lockedTextAnchor = previousAnchor',
              '保存失败，仍已锁定', '保存失败，仍已解锁',
              '[self showLockFeedback:storedLocked ? @"已锁定" : @"已解锁"]'):
    assert token in lock, token
assert lock.index('if (!saved') < lock.index('self.positionLocked = YES')
assert lock.index('if (!saved') < lock.index('self.positionLocked = NO')
pan = body('- (void)handlePan:', '- (BOOL)gestureRecognizer:')
assert pan.index('if (self.positionLocked) return;') < pan.index('self.center =')
assert pan.index('if (self.panBlockedByLock) return;') < pan.index('[self resetInactivityTimer]')
assert 'self.positionLocked = NO' not in pan
assert '[pan requireGestureRecognizerToFail:self.doubleTapGesture]' in s
assert 'SBCPUPanLockBlocked(self.positionLocked,self.panBlockedByLock,pan.state == UIGestureRecognizerStateBegan)' in pan
# Unlocked drag recalculates true logical offsets and persists only when it ends.
assert pan.index('UIGestureRecognizerStateEnded') < pan.index('setFloatPref(CFSTR("floatingTextOnlyY")')
layout = body('static void updateFloatingSize(void) {', 'static void createCPUWindow(void) {')
assert layout.index('if (floatingView.positionLocked)') < layout.index('floatingTextOnlyY')
assert 'resolveLockedTextCenter()' in layout
# Only the verified double-tap unlock assigns NO; reload/reset has no runtime unlock path.
assert s.count('positionLocked = NO') == 1
assert s.count('positionLocked = YES') == 2  # verified toggle + persisted startup restore
print('PASS lock feedback/persistence/rollback/pan-priority/source contracts (not device gesture simulation)')
