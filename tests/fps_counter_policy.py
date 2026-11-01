#!/usr/bin/env python3
"""Static regression checks for the compositor-based FPS sampler."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
s = (root / "Tweak.xm").read_text()
start = s.index("@implementation SBCPUFPSHelper")
end = s.index("@end", start) + 4
helper = s[start:end]
assert "CARenderServerGetDirtyFrameCount" in s
assert "NSTimer" in helper
assert "CADisplayLink" not in helper
assert "maximumFramesPerSecond" not in helper
assert "CAFrameRateRange" not in helper
assert "frameDiff" in helper and "_currentFPS = measured" in helper
assert "displayLinkWithTarget" not in helper
print("FPS compositor-counter policy: passed")
