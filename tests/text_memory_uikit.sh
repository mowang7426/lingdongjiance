#!/bin/bash
set -euo pipefail
TMP_MEM=$(mktemp -d)
trap 'rm -rf "$TMP_MEM"' EXIT
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
xcrun --sdk iphonesimulator clang++ -arch "$ARCH" -isysroot "$SDK" \
  -mios-simulator-version-min=14.0 -x objective-c++ -std=c++11 -fobjc-arc -fblocks -I. \
  -Wall -Wextra -Werror -framework UIKit -framework Foundation \
  -framework CoreText -framework QuartzCore -framework CoreGraphics \
  tests/text_memory_uikit.m SBCPUTextBackdropLabel.m -o "$TMP_MEM/memory-uikit"
xcrun simctl list devices available -j > "$TMP_MEM/devices.json"
DEVICE=$(python3 - "$TMP_MEM/devices.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1])); candidates=[d for k,v in j['devices'].items() if 'iOS' in k for d in v if d.get('isAvailable') and 'iPhone' in d['name']]
assert candidates,'iOS Simulator runtime required'
candidates.sort(key=lambda d:d['state']!='Booted');print(candidates[0]['udid'])
PY
)
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
mkdir -p test-output
SIMCTL_CHILD_SBCPU_PREVIEW_PATH="$PWD/test-output/mem3-uikit-fixture.png" xcrun simctl spawn "$DEVICE" "$TMP_MEM/memory-uikit"
