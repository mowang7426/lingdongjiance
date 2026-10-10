#!/usr/bin/env python3
"""Static contract for the iOS 15 range hook with an iOS 14 deployment target."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = (root / "MotionXPort.xm").read_text()
makefile = (root / "Makefile").read_text()
assert "TARGET = iphone:clang:16.5:14.0" in makefile
assert not re.search(r"-\s*\(void\)\s*setPreferredFrameRateRange:", source)
assert re.search(
    r"static void \(\*SBCPUOriginalSetPreferredFrameRateRange\)"
    r"\(id, SEL, CAFrameRateRange\)\s*API_AVAILABLE\(ios\(15\.0\)\);", source
)
assert re.search(
    r"API_AVAILABLE\(ios\(15\.0\)\)\s*static void "
    r"SBCPUSetPreferredFrameRateRange\(id self, SEL selector, CAFrameRateRange range\)",
    source,
)
assert "range = CAFrameRateRangeMake(120.0f, 120.0f, 120.0f);" in source
assert "SBCPUOriginalSetPreferredFrameRateRange(self, selector, range);" in source
assert re.search(
    r"if \(@available\(iOS 15\.0, \*\)\)\s*\{\s*"
    r"Class displayLinkClass = \[CADisplayLink class\];\s*"
    r"SEL rangeSelector = @selector\(setPreferredFrameRateRange:\);\s*"
    r"if \(\[displayLinkClass instancesRespondToSelector:rangeSelector\]\)\s*\{\s*"
    r"MSHookMessageEx\(displayLinkClass, rangeSelector,\s*"
    r"\(IMP\)SBCPUSetPreferredFrameRateRange,\s*"
    r"\(IMP \*\)&SBCPUOriginalSetPreferredFrameRateRange\);", source
)
assert "CFGetTypeID(value) == CFBooleanGetTypeID()" in source
assert "if (value) CFRelease(value);" in source
print("MotionX availability contract: PASS")
