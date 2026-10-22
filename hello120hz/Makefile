ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk

# Separate target: never mixed into floating HUD, charge or CPU processes.
TWEAK_NAME = 0hello120hz
0hello120hz_FILES = Core/H120Hooks.mm Core/H120RangeTrampolines.S Core/H120Policy.c Shared/H120Preferences.mm
0hello120hz_CFLAGS = -fobjc-arc -IShared
0hello120hz_CCFLAGS = -std=c++17
0hello120hz_FRAMEWORKS = Foundation QuartzCore CoreFoundation
0hello120hz_LIBRARIES = substrate
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
0hello120hz_CFLAGS += -DTHEOS_PACKAGE_SCHEME_ROOTHIDE=1 -I$(THEOS_VENDOR_INCLUDE_PATH)/roothide
0hello120hz_LDFLAGS += -L$(THEOS_VENDOR_LIBRARY_PATH)/iphone/roothide -lroothide
endif
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences" "$(THEOS_STAGING_DIR)/usr/libexec" "$(THEOS_STAGING_DIR)/usr/share/doc/sbcpufloating"
	cp layout/Library/PreferenceLoader/Preferences/hello120hz.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/hello120hz.plist"
	cp install-filter.sh "$(THEOS_STAGING_DIR)/usr/libexec/hello120hz-install"
	chmod 0755 "$(THEOS_STAGING_DIR)/usr/libexec/hello120hz-install"
	cp SOURCE.md CAPABILITIES.md "$(THEOS_STAGING_DIR)/usr/share/doc/sbcpufloating/"
