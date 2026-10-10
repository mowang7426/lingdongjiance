#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <substrate.h>

// SBCPUFloating / MotionX refresh-rate policy port (experimental).
// Preference domain matches the existing SBCPU prefs bundle.
static NSString * const kSBCPURefreshDomain = @"com.yourname.sbcpufloating";
static NSString * const kSBCPURefreshKey = @"system120HzEnabled";

static BOOL SBCPU120HzEnabled(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kSBCPURefreshDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kSBCPURefreshKey,
                                                        (__bridge CFStringRef)kSBCPURefreshDomain);
    BOOL enabled = value ? CFBooleanGetValue((CFBooleanRef)value) : NO;
    if (value) CFRelease(value);
    return enabled;
}

%group SBCPURefreshRateHooks
%hook UIScreen
- (NSInteger)maximumFramesPerSecond {
    if (SBCPU120HzEnabled()) {
        NSInteger original = %orig;
        return original >= 120 ? original : 120;
    }
    return %orig;
}
%end

%hook CADisplayLink
- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    if (SBCPU120HzEnabled() && fps > 0) {
        %orig(120);
        return;
    }
    %orig;
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (SBCPU120HzEnabled()) {
        CAFrameRateRange requested = CAFrameRateRangeMake(120.0f, 120.0f, 120.0f);
        %orig(requested);
        return;
    }
    %orig;
}
%end

%hook SBProMotionPolicy
- (NSInteger)maximumSupportedRefreshRate {
    if (SBCPU120HzEnabled()) {
        NSInteger original = %orig;
        return original >= 120 ? original : 120;
    }
    return %orig;
}
%end

%hook SBDisplayRefreshRateController
- (NSInteger)maximumRefreshRate {
    if (SBCPU120HzEnabled()) {
        NSInteger original = %orig;
        return original >= 120 ? original : 120;
    }
    return %orig;
}
%end
%end

%ctor {
    @autoreleasepool {
        if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            %init(SBCPURefreshRateHooks);
        }
    }
}
