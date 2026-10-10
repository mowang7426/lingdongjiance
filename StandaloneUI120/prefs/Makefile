ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = U120Prefs
U120Prefs_FILES = U120Prefs.m
U120Prefs_FRAMEWORKS = UIKit CoreFoundation
U120Prefs_PRIVATE_FRAMEWORKS = Preferences
U120Prefs_CFLAGS = -fobjc-arc
U120Prefs_INSTALL_PATH = /Library/PreferenceBundles
U120Prefs_RESOURCE_DIRS = Resources
include $(THEOS_MAKE_PATH)/bundle.mk
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/U120Prefs.plist$(ECHO_END)
	$(ECHO_NOTHING)cp Info.plist $(THEOS_STAGING_DIR)/Library/PreferenceBundles/U120Prefs.bundle/Info.plist$(ECHO_END)
