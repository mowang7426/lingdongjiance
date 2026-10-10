ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = StandaloneUI120
StandaloneUI120_FILES = Tweak.m
StandaloneUI120_FRAMEWORKS = UIKit QuartzCore CoreFoundation
StandaloneUI120_CFLAGS = -fobjc-arc -std=gnu11
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
