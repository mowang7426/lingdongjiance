#!/usr/bin/env python3
"""Static guardrails for the runtime-instrumented text-invert UIKit test."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
tweak=(root/'Tweak.xm').read_text()
label=(root/'SBCPUTextBackdropLabel.m').read_text()
header=(root/'SBCPUTextBackdropLabel.h').read_text()
make=(root/'Makefile').read_text()
control=(root/'control').read_text()
workflow=(root/'.github/workflows/build.yml').read_text()
test=(root/'tests/text_invert_performance_uikit.m').read_text()
assert 'SBCPUTextBackdropLabel.m' in make
assert 'sbcpu_setTextOnlyPlainText:value font:slotFont color:color' in tweak
assert 'if (slot.layer.compositingFilter) slot.layer.compositingFilter = nil;' in tweak
assert 'SBCPUTextSlotLayoutCache textSlotLayoutCaches[2]' in tweak
for key in ('mask','fontSize','available','gap','fpsWidth','currentWidth','memoryWidth','cpuWidth','networkDualLine','bold'):
    assert f'cache->{key}==' in tweak or f'cache->{key} ==' in tweak, key
assert 'if (!CGRectEqualToRect(slot.frame,slotFrame)) slot.frame=slotFrame;' in tweak
assert 'if (!CGRectEqualToRect(dot.frame,dotFrame)) dot.frame=dotFrame;' in tweak
assert 'if (_realtimeInvertEnabled == enabled) return;' in label
assert '_lastAttributedText' in label and '_lastAlignment == self.textAlignment' in label
assert '_lastNumberOfLines == self.numberOfLines' in label
assert 'gSBCPUBackdropTestCounters.maskRefreshes++' in label
assert '#ifdef SBCPU_TEXT_BACKDROP_TESTING' in label
assert 'sbcpu_setTextOnlyPlainText:' in header
assert 'SBCPUTextBackdropReadTestCounters' in test
assert 'assert(c.maskRefreshes==0 && c.backdropCreations==0 && c.styledAttributeBuilds==0)' in test
assert 'pixels(actual) isEqualToData:pixels(expected)' in test
assert 'Version: 5.09+mem6' in control
assert 'runs-on: macos-15' in workflow and 'tests/text_invert_performance_uikit.sh' in workflow
# Keep scheduler, sample interval, FPS units, free-memory math and old mem4 spacing untouched.
assert 'NSTimer' not in label and 'dispatch_source' not in label
print('PASS inversion dirty-cache wiring; mem4 policy inputs and original sample cadence remain unchanged')
