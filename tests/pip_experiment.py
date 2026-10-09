#!/usr/bin/env python3
"""Static contract checks for the opt-in public AVKit PiP experiment."""
from pathlib import Path
import plistlib, re

ROOT = Path(__file__).resolve().parents[1]
impl = (ROOT / "SBCPUPiPExperiment.m").read_text()
header = (ROOT / "SBCPUPiPExperiment.h").read_text()
tweak = (ROOT / "Tweak.xm").read_text()
make = (ROOT / "Makefile").read_text()
prefs_impl = (ROOT / "sbcpuprefs/SBCPUPrefsRootListController.m").read_text()
with (ROOT / "sbcpuprefs/Resources/Root.plist").open("rb") as f:
    items = plistlib.load(f)["items"]
filter_text = (ROOT / "SBCPUPiP.plist").read_text()

assert "SBCPUPiP" in re.search(r"^TWEAK_NAME\s*=.*$", make, re.M).group()
assert re.search(r"^SBCPUPiP_FILES\s*=\s*SBCPUPiPExperiment\.m\s*$", make, re.M)
assert re.search(r"^SBCPUPiP_INSTALL_TARGET_PROCESSES\s*=\s*SpringBoard\s*$", make, re.M)
assert '"com.apple.springboard"' in filter_text
assert "Bundles" in filter_text
assert "UIKit" not in filter_text and "Preferences" not in filter_text

switches = [x for x in items if x.get("key") == "pipVideoCallExperimentEnabled"]
assert len(switches) == 1 and switches[0].get("default") is False
for action in ("startPiPExperiment", "stopPiPExperiment", "showPiPExperimentStatus"):
    assert any(x.get("action") == action for x in items), action
    assert f"- (void){action}" in prefs_impl
assert "SBCPUPiPManager" not in prefs_impl and "AVPictureInPicture" not in prefs_impl

assert "AVPictureInPictureVideoCallViewController" in impl
assert "initWithActiveVideoCallSourceView:" in impl
assert "@available(iOS 15.0, *)" in impl
assert "preferredFramesPerSecond = 60" in impl
assert "CMClockGetTime(CMClockGetHostTimeClock())" in impl
assert "CVPixelBufferPoolRelease" in impl
assert "[self.link invalidate]" in impl
assert "flushAndRemoveImage" in impl
assert "kCMSampleAttachmentKey_DisplayImmediately" in impl
assert "UIApplicationProtectedDataWillBecomeUnavailable" in impl
assert "UIWindowDidBecomeHiddenNotification" in impl
assert "UISceneDidDisconnectNotification" in impl
assert "failedToStartPictureInPictureWithError" in impl
assert 'active\": @(state.phase == PIPActive)' in impl
assert "PiPDidStart(&_state, _startGeneration)" in impl
assert "ExperimentEnabled()" in impl

# Explicitly prohibit screenshot/audio/session/private-hook techniques in the experiment target.
for forbidden in ("snapshotViewAfterScreenUpdates", "drawViewHierarchyInRect", "renderInContext:",
                  "AVAudioSession", "MSHook", "%hook", "MotionX"):
    assert forbidden not in impl, forbidden

# Existing lock hook must stop PiP independently of the unrelated lock-cleanup setting.
for signature in ("lockUIFromSource:(long long)source {", "lockUIFromSource:(long long)source withOptions:",
                  "_lockUIFromSource:(long long)source withOptions:"):
    start = tweak.index(signature)
    body = tweak[start:tweak.index("}", start)]
    assert "stopPiPExperimentForLock();" in body
assert tweak.index("static void stopPiPExperimentForLock") < tweak.index("stopPiPExperimentForLock();")

print("PiP experiment static contract: OK")
