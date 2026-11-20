#!/bin/bash
set -euo pipefail
TMP_INV=$(mktemp -d)
trap 'rm -rf "$TMP_INV"' EXIT
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
python3 tests/text_invert_mem5_baseline.py "$TMP_INV"
xcrun --sdk iphonesimulator clang++ -arch "$ARCH" -isysroot "$SDK" \
  -mios-simulator-version-min=14.0 -x objective-c++ -std=c++11 -fobjc-arc -fblocks \
  -DSBCPU_TEXT_BACKDROP_TESTING=1 -I. -I"$TMP_INV" -Wall -Wextra -Werror \
  -framework UIKit -framework Foundation -framework CoreText -framework QuartzCore -framework CoreGraphics \
  tests/text_shared_live_uikit.m SBCPUTextBackdropLabel.m "$TMP_INV/SBCPUMem5TextBackdropLabel.m" -o "$TMP_INV/shared-live-uikit"
xcrun simctl list devices available -j > "$TMP_INV/devices.json"
DEVICE=$(python3 - "$TMP_INV/devices.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1])); ds=[d for k,v in j['devices'].items() if 'iOS' in k for d in v if d.get('isAvailable') and 'iPhone' in d['name']]
assert ds, 'UIKit instrumentation requires an available iOS Simulator runtime'
ds.sort(key=lambda d:d['state']!='Booted'); print(ds[0]['udid'])
PY
)
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
mkdir -p test-output
SIMCTL_CHILD_SBCPU_SHARED_LIVE_RESULT_PATH="$PWD/test-output/text-shared-live.json" \
  xcrun simctl spawn "$DEVICE" "$TMP_INV/shared-live-uikit"
