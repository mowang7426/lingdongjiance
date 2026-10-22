#!/bin/sh
# Called by the existing package postinst with its validated jailbreak root.
# No preference values, process restarts, HUD or recording actions here.
set -eu
base=${1:-}
[ -n "$base" ] || base=/
case "$base" in /*) ;; *) exit 1;; esac
[ -f "$base/Library/PreferenceBundles/hello120hz.bundle/DefaultInjection.plist" ] || exit 1
[ -f "$base/Library/MobileSubstrate/DynamicLibraries/0hello120hz.dylib" ] || exit 1
directory="$base/var/mobile/Library/Preferences"
# Create only missing directories; never chown/chmod a pre-existing shared parent.
for relative in var var/mobile var/mobile/Library var/mobile/Library/Preferences; do
    target="$base/$relative"
    if [ ! -d "$target" ]; then
        mkdir "$target"
        chown 501:501 "$target"
        chmod 0755 "$target"
    fi
done
preferences="$directory/cn.zqbb.fix120hz.injection.plist"
[ ! -L "$preferences" ] || exit 1
if [ ! -e "$preferences" ]; then
    cp "$base/Library/PreferenceBundles/hello120hz.bundle/DefaultInjection.plist" "$preferences"
    chown 501:501 "$preferences"
    chmod 0644 "$preferences"
fi
loader="$base/Library/MobileSubstrate/DynamicLibraries/0hello120hz.plist"
# Exact package-owned filter only. Its mobile-owned target permits atomic UI writes.
rm -f "$loader"
ln -s ../../../var/mobile/Library/Preferences/cn.zqbb.fix120hz.injection.plist "$loader"
