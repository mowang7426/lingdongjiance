#!/bin/bash
set -euo pipefail
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
clang -std=c11 -Wall -Wextra -Werror tests/h120_policy.c hello120hz/Core/H120Policy.c -o "$TMP/policy"
"$TMP/policy"
clang++ -x c++ -std=c++11 -Wall -Wextra -Werror tests/h120_policy.c hello120hz/Core/H120Policy.c -o "$TMP/policy-cxx"
"$TMP/policy-cxx"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
xcrun --sdk iphonesimulator clang++ -arch "$ARCH" -isysroot "$SDK" -mios-simulator-version-min=15.0 \
 -std=c++17 -fobjc-arc -fblocks -Itests/h120_stubs -I. -Wno-nullability-completeness \
 -framework UIKit -framework Foundation -framework QuartzCore -framework CoreFoundation \
 tests/h120_ui.mm -o "$TMP/h120-ui"
xcrun simctl list devices available -j > "$TMP/devices.json"
DEVICE=$(python3 - "$TMP/devices.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]));d=[v for k,a in j['devices'].items() if 'iOS' in k for v in a if v.get('isAvailable') and 'iPhone' in v['name']];assert d;d.sort(key=lambda v:v['state']!='Booted');print(d[0]['udid'])
PY
)
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl spawn "$DEVICE" "$TMP/h120-ui"
