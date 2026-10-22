TARGET := iphone:clang:16.5:15.0
DEBUG := 0
FINALPACKAGE := 1

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = hello120hz
hello120hz_FILES = Hello120HzPreferences.mm H120SettingsController.mm ../Shared/H120Preferences.mm ../Shared/H120RecordingDiagnostics.c
hello120hz_CFLAGS = -fobjc-arc -Wall -Wextra -ffile-prefix-map=$(THEOS_PROJECT_DIR)=. -fdebug-prefix-map=$(THEOS_PROJECT_DIR)=.
hello120hz_CCFLAGS = -std=c++17
hello120hz_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers QuartzCore CoreGraphics
hello120hz_PRIVATE_FRAMEWORKS = Preferences
hello120hz_INSTALL_PATH = /Library/PreferenceBundles
hello120hz_RESOURCE_DIRS = Resources

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
hello120hz_CFLAGS += -DTHEOS_PACKAGE_SCHEME_ROOTHIDE=1 -I$(THEOS_VENDOR_INCLUDE_PATH)/roothide
hello120hz_LDFLAGS += -L$(THEOS_VENDOR_LIBRARY_PATH)/iphone/roothide -lroothide
endif
include $(THEOS_MAKE_PATH)/bundle.mk
