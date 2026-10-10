#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// Same explicit CFPreferences scope as Settings. Read only at bootstrap / events.
static NSString * const kSBCPURefreshDomain = @"com.yourname.sbcpufloating";
static NSString * const kSBCPURefreshKey = @"system120HzEnabled";
static BOOL SBCPURefreshEnabledForKey(NSString *key) {
    CFPreferencesSynchronize((__bridge CFStringRef)kSBCPURefreshDomain,
                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef value = CFPreferencesCopyValue((__bridge CFStringRef)key,
        (__bridge CFStringRef)kSBCPURefreshDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL enabled = NO;
    if (value && CFGetTypeID(value) == CFBooleanGetTypeID()) {
        enabled = CFBooleanGetValue((CFBooleanRef)value);
    } else if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
        enabled = [(__bridge NSNumber *)value boolValue];
    }
    if (value) CFRelease(value);
    return enabled;
}
static BOOL SBCPU120HzEnabled(void) { return SBCPURefreshEnabledForKey(kSBCPURefreshKey); }
static BOOL SBCPUDynamic120HzEnabled(void) { return SBCPURefreshEnabledForKey(@"dynamicSource120HzEnabled"); }
#import "SBCPUHiddenTextExperiment.h"
#import "SBCPURefreshRuntime.h"

%ctor {
    @autoreleasepool {
        if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            // UIKit/SpringBoard initialization is not complete in dyld constructors.
            dispatch_async(dispatch_get_main_queue(), ^{ [[SBCPURefreshRuntime shared] start]; });
        }
    }
}
