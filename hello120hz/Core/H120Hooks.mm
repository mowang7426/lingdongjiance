#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <notify.h>
#include <dlfcn.h>
#include <atomic>
#include <cstring>
#import "../Shared/H120Preferences.h"
#include "H120Policy.h"
#include "H120Runtime.h"
#include "../Shared/H120RecordingDiagnostics.h"
#include <unistd.h>

extern "C" {
alignas(4) uint32_t H120ActiveFPSBits = 0;
void *H120OriginalRangeTimingsBB = nullptr;
void *H120OriginalRangeTimingsB = nullptr;
void *H120OriginalRangeConvert = nullptr;
void *H120OriginalRangeSource = nullptr;
void *H120OriginalRangeItemLocked = nullptr;
void *H120OriginalRangeItem = nullptr;
void H120RangeTimingsBB(void);
void H120RangeTimingsB(void);
void H120RangeConvert(void);
void H120RangeSource(void);
void H120RangeItemLocked(void);
void H120RangeItem(void);
}

static std::atomic<bool> featureEnabled(false);
static std::atomic<uint32_t> configuredFPS(120);
static std::atomic<unsigned> clientHookCount(0);
static void H120PublishClientDiagnostic(void) {
    NSString *path = H120PreferencesPath();
    H120DiagnosticUpdateClient(clientHookCount.load(), featureEnabled.load(),
        path && access(path.fileSystemRepresentation, R_OK) == 0, configuredFPS.load());
}
static bool (*originalArbitration)(void);
static bool (*originalRestriction)(void);
uint32_t H120ConfiguredFPS(void) { return configuredFPS.load(std::memory_order_relaxed); }
bool H120FeatureEnabled(void) { return featureEnabled.load(std::memory_order_relaxed); }

static void *H120Symbol(const char *name) {
    static MSImageRef image = MSGetImageByName("/System/Library/Frameworks/QuartzCore.framework/QuartzCore");
    return image ? MSFindSymbol(image, name) : nullptr;
}

static bool H120Install(const char *name, void *replacement, void **original) {
    void *symbol = H120Symbol(name);
    if (!symbol) { NSLog(@"[Hello120Hz] symbol unavailable: %s", name); return false; }
    MSHookFunction(symbol, replacement, original);
    if (*original) clientHookCount.fetch_add(1);
    return *original != nullptr;
}

static void H120InstallRange(const char *name, void (*replacement)(void), void **slot) {
    H120Install(name, (void *)replacement, slot);
}

static bool H120Arbitration(void) {
    return H120FeatureEnabled() ? true : originalArbitration();
}

static bool H120Restriction(void) {
    return H120FeatureEnabled() ? false : originalRestriction();
}

static bool H120CurrentProcessExcluded(NSDictionary *preferences) {
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
    id excluded = preferences[@"selectedApps"];
    if (!identifier) return false;
    return [excluded isKindOfClass:NSArray.class] && [excluded containsObject:identifier];
}

static void H120ReloadPreferences(void) {
    NSDictionary *preferences = H120ReadPreferences();
    id rate = preferences[@"wantsFPS"];
    float fps = [rate respondsToSelector:@selector(floatValue)] ? [rate floatValue] : 120.0f;
    fps = H120NormalizeFPS(fps);
    configuredFPS.store((uint32_t)fps, std::memory_order_relaxed);
    bool enabled = H120ClientEnabled([preferences[@"wantsEnable"] boolValue], H120CurrentProcessExcluded(preferences));
    featureEnabled.store(enabled, std::memory_order_relaxed);
    uint32_t bits = 0;
    if (enabled) std::memcpy(&bits, &fps, sizeof(bits));
    __atomic_store_n(&H120ActiveFPSBits, bits, __ATOMIC_RELEASE);
    H120PublishClientDiagnostic();
}

static void H120DistributedPreferences(CFNotificationCenterRef center, void *observer,
    CFNotificationName name, const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)name; (void)object; (void)info;
    dispatch_async(dispatch_get_main_queue(), ^{ H120ReloadPreferences(); });
}

static void H120InstallClientHooks(void) {
    H120InstallRange("__ZN2CA7Display21DisplayTimingsControl33fps_range_to_frame_interval_rangeE16CAFrameRateRangebb",
                     H120RangeTimingsBB, &H120OriginalRangeTimingsBB);
    H120InstallRange("__ZN2CA7Display21DisplayTimingsControl33fps_range_to_frame_interval_rangeE16CAFrameRateRangeb",
                     H120RangeTimingsB, &H120OriginalRangeTimingsB);
    H120InstallRange("__Z36CAFrameRateRangeToFrameIntervalRange16CAFrameRateRangedhbbb",
                     H120RangeConvert, &H120OriginalRangeConvert);
    H120InstallRange("__ZN2CA22DynamicFrameRateSource23set_preferred_fps_rangeE16CAFrameRateRangeb",
                     H120RangeSource, &H120OriginalRangeSource);
    H120InstallRange("__ZN2CA7Display15DisplayLinkItem30set_preferred_fps_range_lockedE16CAFrameRateRangeb",
                     H120RangeItemLocked, &H120OriginalRangeItemLocked);
    H120InstallRange("__ZN2CA7Display15DisplayLinkItem23set_preferred_fps_rangeE16CAFrameRateRangebb",
                     H120RangeItem, &H120OriginalRangeItem);
    H120Install("__Z35CADisplayEnableFrameRateArbitrationv", (void *)H120Arbitration, (void **)&originalArbitration);
    H120Install("__Z39CADisplayEnableHighFrameRateRestrictionv", (void *)H120Restriction, (void **)&originalRestriction);
}

// The uploaded backboardd return ABI is not evidenced by the symbol names.
// No backboardd / replayd injection or guessed function call is shipped.
__attribute__((constructor)) static void H120Initialize(void) {
    if (strcmp(getprogname(), "SpringBoard") == 0) H120DiagnosticStartNamed(H120_CLIENT_DIAGNOSTIC_PING);
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        if ([process isEqualToString:@"backboardd"] || [process isEqualToString:@"replayd"]) return;
        H120ReloadPreferences(); // initial disabled/default/exclusion state BEFORE installing hooks
        H120InstallClientHooks();
        H120PublishClientDiagnostic();
        NSLog(@"[Hello120Hz] client hooks installed where symbols exist; backboard cadence unavailable (unverified ABI); recording uses separate replayd-only module");
        static int preferencesToken;
        notify_register_dispatch(H120PreferencesNotification.UTF8String, &preferencesToken,
                                 dispatch_get_main_queue(), ^(int token) {
            (void)token; H120ReloadPreferences();
        });
        CFNotificationCenterRef center = H120DistributedNotificationCenter();
        if (center) CFNotificationCenterAddObserver(center, NULL, H120DistributedPreferences,
            (__bridge CFStringRef)H120PreferencesNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
