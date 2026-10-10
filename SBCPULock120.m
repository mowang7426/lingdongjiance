#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/sysctl.h>
#import "SBCPULock120Policy.h"

// A SpringBoard-local high-rate request, not a global panel override. Nothing
// hooks other applications, animation frame rates or the compositor.
static NSString *const SB120Domain = @"com.yourname.sbcpufloating";
static const char *const SB120Changed = "com.yourname.sbcpufloating/settingsChanged";

@interface SB120Keeper : NSObject
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic, strong) NSTimer *watchdog;
@property(nonatomic) int notificationToken;
@property(nonatomic) BOOL enabled;
- (void)refresh;
@end

@implementation SB120Keeper
- (BOOL)supported {
    if (@available(iOS 15.0, *)) {
        size_t length = 0;
        if (sysctlbyname("hw.machine", NULL, &length, NULL, 0) != 0 || length < 2 || length > 64) return NO;
        char model[64] = {0};
        if (sysctlbyname("hw.machine", model, &length, NULL, 0) != 0 || strcmp(model, "iPhone15,3")) return NO;
        return [UIScreen mainScreen].maximumFramesPerSecond >= 120;
    }
    return NO;
}
- (BOOL)unlocked {
    Class manager = NSClassFromString(@"SBLockScreenManager");
    SEL shared = @selector(sharedInstance), locked = @selector(isUILocked);
    if (!manager || ![manager respondsToSelector:shared]) return NO;
    id instance = ((id (*)(id, SEL))objc_msgSend)(manager, shared);
    if (!instance || ![instance respondsToSelector:locked]) return NO;
    return !((BOOL (*)(id, SEL))objc_msgSend)(instance, locked);
}
- (void)refresh {
    NSAssert([NSThread isMainThread], @"SB120 must run on the main thread");
    CFPreferencesSynchronize((__bridge CFStringRef)SB120Domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef pref = CFPreferencesCopyValue(CFSTR("springBoard120HzEnabled"), (__bridge CFStringRef)SB120Domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    self.enabled = pref && CFGetTypeID(pref) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)pref);
    if (pref) CFRelease(pref);
    if (!self.enabled || ![self supported]) {
        [self.link invalidate]; self.link = nil;
        [self.watchdog invalidate]; self.watchdog = nil;
        return;
    }
    if (!self.watchdog) {
        self.watchdog = [NSTimer timerWithTimeInterval:2.0 target:self selector:@selector(reconcile) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.watchdog forMode:NSRunLoopCommonModes];
    }
    [self reconcile];
}
- (void)reconcile {
    NSProcessInfo *info = [NSProcessInfo processInfo];
    BOOL active = SB120Active(self.enabled, [UIScreen mainScreen].maximumFramesPerSecond,
        [UIApplication sharedApplication].applicationState == UIApplicationStateActive && [self unlocked],
        info.lowPowerModeEnabled, (int)info.thermalState);
    if (!active) { [self.link invalidate]; self.link = nil; return; }
    if (self.link) return;
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    if (@available(iOS 15.0, *)) {
        link.preferredFrameRateRange = CAFrameRateRangeMake(120, 120, 120);
    }
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.link = link;
}
- (void)tick:(CADisplayLink *)link { (void)link; }
- (void)stopForState:(NSNotification *)note { (void)note; [self reconcile]; }
- (instancetype)init {
    if ((self = [super init])) {
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        for (NSString *name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification,
                UIApplicationProtectedDataWillBecomeUnavailable, UIApplicationProtectedDataDidBecomeAvailable]) {
            [nc addObserver:self selector:@selector(stopForState:) name:name object:nil];
        }
        __weak typeof(self) weakSelf = self;
        notify_register_dispatch(SB120Changed, &_notificationToken, dispatch_get_main_queue(), ^(int token) {
            (void)token; [weakSelf refresh];
        });
        [self refresh];
    }
    return self;
}
- (void)dealloc {
    if (_notificationToken) notify_cancel(_notificationToken);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_link invalidate]; [_watchdog invalidate];
}
@end

__attribute__((constructor)) static void SB120Initialize(void) {
    if (![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"]) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        static SB120Keeper *keeper;
        keeper = [SB120Keeper new];
    });
}
