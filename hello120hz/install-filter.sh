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
# The filter is owned entirely by this plugin. Migrate the existing generated
# XML without dropping the user's All Apps mode. No other preference keys live
# in this file; wantsEnable/recordingEnabled/selectedApps are a separate plist.
resource="$base/Library/PreferenceBundles/hello120hz.bundle"
template="$resource/DefaultInjection.plist"
if [ -e "$preferences" ]; then
    case "$(cat "$preferences")" in
        *com.apple.UIKit*) template="$resource/AllInjection.plist" ;;
    esac
fi
[ -f "$template" ] || exit 1
# Atomic replacement also repairs full5's persisted missing-replayd filter.
temporary="$preferences.full6.$$"
(umask 077; set -C; cat "$template" > "$temporary") || exit 1
chown 501:501 "$temporary"
chmod 0644 "$temporary"
mv -f "$temporary" "$preferences"
# Upgrade cleanup is limited to exact legacy filenames owned by this package.
# $base was supplied by the existing validated rootless/roothide postinst.
rm -f "$base/Library/MobileSubstrate/DynamicLibraries/0hello120hzRecording.dylib" \
      "$base/Library/MobileSubstrate/DynamicLibraries/0hello120hzRecording.plist"
loader="$base/Library/MobileSubstrate/DynamicLibraries/0hello120hz.plist"
# Exact package-owned filter only. Its mobile-owned target permits atomic UI writes.
rm -f "$loader"
ln -s ../../../var/mobile/Library/Preferences/cn.zqbb.fix120hz.injection.plist "$loader"
