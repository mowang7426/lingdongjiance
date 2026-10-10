#!/usr/bin/env python3
from pathlib import Path
import plistlib, re
r=Path(__file__).parents[1]
s=(r/"sbcpuprefs/SBCPUPrefsRootListController.m").read_text()
p=(r/"sbcpuprefs/Resources/Root.plist").read_bytes()
items=plistlib.loads(p)["items"]
keys={x.get("key"):x for x in items if x.get("key")}
assert keys["system120HzEnabled"].get("defaults") is None
for k in ("thermalPowerMode","thermalPreventDimmingEnabled","thermalSuppressNotificationsEnabled","thermalDisablePocketSunlightEnabled","thermalSunlightLockedEnabled"):
 assert keys[k].get("defaults") is None, k
assert "NSDictionary *verified" in s and "verified[key]" in s
assert 'return [specifier propertyForKey:@"default"] ?: @NO;' in s
assert "InsulationWritePref(key, value)" in s
assert "CFPreferencesSetValue" in s and "kCFPreferencesCurrentUser" in s
print("switch persistence mapping, atomic readback, and non-nil getter: PASS")
