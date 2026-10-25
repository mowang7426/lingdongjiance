#import "SBCPUPeachDockConfig.h"
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <stdatomic.h>
// Same domain as the existing panel. Settings are restart-latched, so layout
// never sees a partially changed mode and hot paths never read preferences.
static atomic_uint SBCPUPeachDockFlags;
void SBCPUPeachDockLoadSnapshot(void) {
    NSString *domain = @"com.yourname.sbcpufloating";
    NSArray *keys = @[@"peachDockEnabled", @"peachDockPaging", @"peachDockSpring", @"peachDockEdge"];
    unsigned flags = 0;
    for (NSUInteger i = 0; i < keys.count; ++i) {
        id value = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)keys[i],
            (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        BOOL fallback = i == 1 || i == 2;
        BOOL enabled = [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
        if (enabled) flags |= 1U << i;
    }
    atomic_store(&SBCPUPeachDockFlags, flags);
}
BOOL SBCPUPeachDockRequested(void) { return (atomic_load(&SBCPUPeachDockFlags) & 1U) != 0; }
BOOL SBCPUPeachDockPaging(void) { return (atomic_load(&SBCPUPeachDockFlags) & 2U) != 0; }
BOOL SBCPUPeachDockSpring(void) { return (atomic_load(&SBCPUPeachDockFlags) & 4U) != 0; }
BOOL SBCPUPeachDockEffects(void) {
    NSProcessInfo *p = NSProcessInfo.processInfo;
    return SBCPUPeachDockVisualPolicy((atomic_load(&SBCPUPeachDockFlags) & 8U) != 0,
        p.lowPowerModeEnabled, (int)p.thermalState, UIAccessibilityIsReduceMotionEnabled(),
        UIAccessibilityIsReduceTransparencyEnabled());
}
BOOL SBCPUPeachDockConflict(void) {
    if (objc_getClass("IF16EdgeTransition") != Nil) return YES;
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        NSString *image = name ? [[NSString stringWithUTF8String:name] lowercaseString] : @"";
        if ([image containsString:@"infinidock"]) return YES;
    }
    return NO;
}
