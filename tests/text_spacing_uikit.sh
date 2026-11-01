#!/bin/bash
set -euo pipefail
TMP_SPACING=$(mktemp -d)
trap 'rm -rf "$TMP_SPACING"' EXIT
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
xcrun --sdk iphonesimulator clang++ -arch "$ARCH" -isysroot "$SDK" \
  -mios-simulator-version-min=14.0 -x objective-c++ -std=c++11 -fobjc-arc -fblocks -I. \
  -Wall -Wextra -Werror -framework UIKit -framework Foundation \
  -framework CoreText -framework QuartzCore -framework CoreGraphics \
  tests/text_spacing_uikit.m SBCPUTextBackdropLabel.m -o "$TMP_SPACING/spacing-uikit"
xcrun simctl list devices available -j > "$TMP_SPACING/devices.json"
DEVICE=$(python3 - "$TMP_SPACING/devices.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1])); candidates=[d for k,v in j['devices'].items() if 'iOS' in k for d in v if d.get('isAvailable') and 'iPhone' in d['name']]
assert candidates,'iOS Simulator runtime required'
candidates.sort(key=lambda d:d['state']!='Booted');print(candidates[0]['udid'])
PY
)
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
mkdir -p test-output
SIMCTL_CHILD_SBCPU_SPACING_OUTPUT="$PWD/test-output" xcrun simctl spawn "$DEVICE" "$TMP_SPACING/spacing-uikit"
