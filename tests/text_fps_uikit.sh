#!/bin/bash
# Fail rather than silently substituting AppKit for UIKit.
set -euo pipefail
TMP_FPS=$(mktemp -d)
trap 'rm -rf "$TMP_FPS"' EXIT
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
xcrun --sdk iphonesimulator clang -arch "$ARCH" -isysroot "$SDK" \
  -mios-simulator-version-min=14.0 -fobjc-arc -fblocks -I. \
  -Wall -Wextra -Werror -framework UIKit -framework Foundation \
  -framework CoreText -framework QuartzCore \
  tests/text_fps_uikit.m SBCPUTextBackdropLabel.m -o "$TMP_FPS/fps-uikit"
xcrun simctl list devices available -j > "$TMP_FPS/devices.json"
DEVICE=$(python3 - "$TMP_FPS/devices.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
candidates=[d for k,v in j['devices'].items() if 'iOS' in k for d in v if d.get('isAvailable') and 'iPhone' in d['name']]
assert candidates, 'UIKit validation requires an available iOS Simulator runtime'
candidates.sort(key=lambda d:d['state']!='Booted')
print(candidates[0]['udid'])
PY
)
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl spawn "$DEVICE" "$TMP_FPS/fps-uikit"
