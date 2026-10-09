// Independent source implementation; no MotionX binaries or code incorporated.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>
#include <stdatomic.h>
#include <stdlib.h>
#import "SBCPUHighRefreshPolicy.h"
#import "SBCPUHighRefreshPreferences.h"

static atomic_bool gEnabled = ATOMIC_VAR_INIT(false);
static bool gSupported;
static int gNotifyToken;
static NSInteger (*gScreenOriginal)(id, SEL);
static NSInteger (*gPolicyOriginal)(id, SEL);
static NSInteger (*gControllerOriginal)(id, SEL);
static void (*gFPSOriginal)(id, SEL, NSInteger);
static void (*gRangeOriginal)(id, SEL, CAFrameRateRange) API_AVAILABLE(ios(15.0));
static bool Enabled(void) { return atomic_load_explicit(&gEnabled, memory_order_acquire); }

static bool MethodMatches(Method method, const char *ret, const char *arg) {
    if (!method) return false;
    unsigned count = method_getNumberOfArguments(method);
    char *r = method_copyReturnType(method);
    char *s = count > 0 ? method_copyArgumentType(method, 0) : NULL;
    char *c = count > 1 ? method_copyArgumentType(method, 1) : NULL;
    char *a = count > 2 ? method_copyArgumentType(method, 2) : NULL;
    bool matches = SBHRABI(r, count, s, c, a, ret, arg);
    free(r); free(s); free(c); free(a);
    return matches;
}
static void Install(Class cls, SEL selector, const char *ret, const char *arg, IMP replacement, IMP *original) {
    if (!cls || !MethodMatches(class_getInstanceMethod(cls, selector), ret, arg)) return;
    MSHookMessageEx(cls, selector, replacement, original);
}
static NSInteger ScreenMaximum(id object, SEL selector) {
    if (!Enabled() || !gSupported) return gScreenOriginal(object, selector);
    return 120;
}
static NSInteger PolicyMaximum(id object, SEL selector) {
    if (!Enabled() || !gSupported) return gPolicyOriginal(object, selector);
    return 120;
}
static NSInteger ControllerMaximum(id object, SEL selector) {
    if (!Enabled() || !gSupported) return gControllerOriginal(object, selector);
    return 120;
}
static void PreferredFPS(id object, SEL selector, NSInteger fps) {
    gFPSOriginal(object, selector, (NSInteger)SBHRFPS(fps, Enabled(), gSupported));
}
static void PreferredRange(id object, SEL selector, CAFrameRateRange range) API_AVAILABLE(ios(15.0)) {
    // Pass the exact original struct for disabled/unsupported/non-finite inputs.
    if (!Enabled() || !gSupported || !isfinite(range.minimum) ||
        !isfinite(range.maximum) || !isfinite(range.preferred)) {
        gRangeOriginal(object, selector, range);
        return;
    }
    SBHRRange selected = SBHRFrameRange((SBHRRange){range.minimum, range.maximum, range.preferred}, true, true);
    range.minimum = selected.minimum;
    range.maximum = selected.maximum;
    range.preferred = selected.preferred;
    gRangeOriginal(object, selector, range);
}
static void RefreshPreference(void) {
    atomic_store_explicit(&gEnabled, SBHRReadEnabled(), memory_order_release);
}
static void InstallOnce(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"] ||
            ![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        Class screenClass = [UIScreen class];
        SEL maximum = @selector(maximumFramesPerSecond);
        Method method = class_getInstanceMethod(screenClass, maximum);
        if (!MethodMatches(method, @encode(NSInteger), NULL)) return;
        // Snapshot the pre-install original IMP, never our spoofed getter. Other
        // tweaks loaded earlier can still affect this value; do not claim HW proof.
        NSInteger (*original)(id, SEL) = (NSInteger (*)(id, SEL))method_getImplementation(method);
        UIScreen *screen = [UIScreen mainScreen];
        if (!screen || !original || original(screen, maximum) < 120) return;
        gSupported = true; // Immutable after installation on the main queue.
        // Fail closed if event registration fails; do not enable without live off.
        if (notify_register_dispatch(SBHR_NOTIFY, &gNotifyToken, dispatch_get_main_queue(), ^(int token) {
            (void)token;
            RefreshPreference();
        }) != NOTIFY_STATUS_OK) return;
        Install(screenClass, maximum, @encode(NSInteger), NULL, (IMP)ScreenMaximum, (IMP *)&gScreenOriginal);
        Install([CADisplayLink class], @selector(setPreferredFramesPerSecond:), @encode(void),
            @encode(NSInteger), (IMP)PreferredFPS, (IMP *)&gFPSOriginal);
        if (@available(iOS 15.0, *)) {
            Install([CADisplayLink class], @selector(setPreferredFrameRateRange:), @encode(void),
                @encode(CAFrameRateRange), (IMP)PreferredRange, (IMP *)&gRangeOriginal);
        }
        // Only exact NSInteger ABI is supported. Float/double, unsigned integer,
        // other widths, missing classes/selectors: skip, never guess a private ABI.
        Install(NSClassFromString(@"SBProMotionPolicy"), NSSelectorFromString(@"maximumSupportedRefreshRate"),
            @encode(NSInteger), NULL, (IMP)PolicyMaximum, (IMP *)&gPolicyOriginal);
        Install(NSClassFromString(@"SBDisplayRefreshRateController"), NSSelectorFromString(@"maximumRefreshRate"),
            @encode(NSInteger), NULL, (IMP)ControllerMaximum, (IMP *)&gControllerOriginal);
        RefreshPreference();
    });
}
__attribute__((constructor)) static void SBHRInitialize(void) {
    // UIKit capability query/hook installation on main, exactly once. No timers,
    // display-link registry, per-frame preferences reads, or automatic respring.
    dispatch_async(dispatch_get_main_queue(), ^{ InstallOnce(); });
}
