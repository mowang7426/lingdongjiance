#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>
#include <stdatomic.h>
#include <string.h>
#import "Policy.h"

static CFStringRef const Domain = CFSTR("com.mowang.ui120");
static atomic_bool Enabled;
static NSInteger Hardware;
static int LockToken = -1;
static BOOL HookReady;
static void (*OriginalRange)(CADisplayLink *, SEL, CAFrameRateRange);
static __thread unsigned Bypass;
static NSHashTable<CADisplayLink *> *Touched;
static char SavedKey;
static void Restore(void) {
    if (!NSThread.isMainThread || !OriginalRange) return;
    for (CADisplayLink *link in Touched.allObjects) {
        @synchronized (link) {
            NSValue *saved = objc_getAssociatedObject(link, &SavedKey);
            if (!saved) continue;
            CAFrameRateRange range;
            [saved getValue:&range size:sizeof(range)];
            objc_setAssociatedObject(link, &SavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ++Bypass;
            OriginalRange(link, @selector(setPreferredFrameRateRange:), range);
            --Bypass;
        }
    }
    [Touched removeAllObjects];
}

static void Reload(void) {
    CFPreferencesAppSynchronize(Domain);
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue(CFSTR("Enabled"), Domain, &valid);
    atomic_store(&Enabled, valid && value);
}
static BOOL Locked(void) {
    uint64_t state = 1;
    return LockToken < 0 || notify_get_state(LockToken, &state) != NOTIFY_STATUS_OK || state != 0;
}
static BOOL Safe(void) {
    NSProcessInfo *p = NSProcessInfo.processInfo;
    return U120Safe(atomic_load(&Enabled), (int)Hardware, Locked(),
                   p.lowPowerModeEnabled, (int)p.thermalState, NSThread.isMainThread);
}
static void SetRange(CADisplayLink *link, SEL cmd, CAFrameRateRange range) {
    if (Bypass) { OriginalRange(link, cmd, range); return; }
    @synchronized (link) {
        // A background setter cancels this link's saved request, avoiding stale restoration.
        if (Safe() && U120Eligible(range.minimum, range.maximum, range.preferred)) {
            objc_setAssociatedObject(link, &SavedKey,
                [NSValue value:&range withObjCType:@encode(CAFrameRateRange)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [Touched addObject:link]; // Safe() implies main thread; weak table never retains links.
            range = CAFrameRateRangeMake(120,120,120);
        } else {
            objc_setAssociatedObject(link, &SavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (NSThread.isMainThread) [Touched removeObject:link];
        }
        ++Bypass;
        OriginalRange(link, cmd, range);
        --Bypass;
    }
}
static BOOL ValidABI(Method method) {
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char result[32], object[32], selector[32], range[128];
    method_getReturnType(method, result, sizeof(result));
    method_getArgumentType(method, 0, object, sizeof(object));
    method_getArgumentType(method, 1, selector, sizeof(selector));
    method_getArgumentType(method, 2, range, sizeof(range));
    return !strcmp(result, @encode(void)) && !strcmp(object, @encode(id)) &&
           !strcmp(selector, @encode(SEL)) && !strcmp(range, @encode(CAFrameRateRange));
}
static void SaveDiagnostic(NSString *text) {
    CFPreferencesSetAppValue(CFSTR("Diagnostic"), (__bridge CFStringRef)text, Domain);
    CFPreferencesAppSynchronize(Domain);
    notify_post("com.mowang.ui120.diagnostic.ready");
}
@interface U120Probe : NSObject
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic) CFTimeInterval start;
@property(nonatomic) CFTimeInterval last;
@property(nonatomic) CFTimeInterval total;
@property(nonatomic) NSUInteger samples;
@property(nonatomic) CFTimeInterval maxGap;
@property(nonatomic) BOOL cancelled;
- (void)tick:(CADisplayLink *)link;
- (void)finish;
@end
static U120Probe *Probe;
@implementation U120Probe
- (void)tick:(CADisplayLink *)link {
    if (!Safe()) { self.cancelled = YES; [self finish]; return; }
    CFTimeInterval now = link.timestamp;
    if (!self.start) self.start = now;
    if (self.last && now > self.last) {
        CFTimeInterval dt = now - self.last;
        self.total += dt;
        self.maxGap = MAX(self.maxGap, dt);
        ++self.samples;
    }
    self.last = now;
    if (now - self.start >= 3) [self finish];
}
- (void)finish {
    if (Probe != self) return;
    [self.link invalidate]; self.link = nil;
    double hz = self.total > 0 ? self.samples / self.total : 0;
    SaveDiagnostic([NSString stringWithFormat:
        @"%@\n原始硬件上限=%ld；range ABI=%@；启用=%@\n3秒独立探针回调=%.2fHz；样本=%lu；最大间隔=%.2fms；%@\n这是CADisplayLink回调测量，不是面板扫描率，也不证明其他视图/游戏达到120。",
        NSDate.date, (long)Hardware, HookReady ? @"通过" : @"未安装",
        atomic_load(&Enabled) ? @"是" : @"否", hz, (unsigned long)self.samples,
        self.maxGap * 1000, self.cancelled ? @"保护触发/超时" : @"完成"]);
    Probe = nil;
}
@end
static void Diagnose(void) {
    if (Probe) return;
    if (!HookReady || !Safe()) {
        SaveDiagnostic([NSString stringWithFormat:
            @"%@\n不启动探针：原始硬件上限=%ld；ABI=%@；启用=%@；锁屏/未知=%@；低电量=%@；热状态=%ld。仅nominal解锁状态允许。",
            NSDate.date, (long)Hardware, HookReady ? @"通过" : @"拒绝",
            atomic_load(&Enabled) ? @"是" : @"否", Locked() ? @"是" : @"否",
            NSProcessInfo.processInfo.lowPowerModeEnabled ? @"是" : @"否",
            (long)NSProcessInfo.processInfo.thermalState]);
        return;
    }
    Probe = [U120Probe new];
    Probe.link = [CADisplayLink displayLinkWithTarget:Probe selector:@selector(tick:)];
    Probe.link.preferredFrameRateRange = CAFrameRateRangeMake(120,120,120);
    [Probe.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    // One-shot watchdog releases a paused probe as well; no recurring timer.
    U120Probe *current = Probe;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (Probe == current) { current.cancelled = YES; [current finish]; }
    });
}
__attribute__((constructor)) static void Init(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            Touched = [NSHashTable weakObjectsHashTable];
            Hardware = UIScreen.mainScreen.maximumFramesPerSecond; // before any hook we install
            Reload();
            if (notify_register_check("com.apple.springboard.lockstate", &LockToken) != NOTIFY_STATUS_OK)
                LockToken = -1;
            Method m = class_getInstanceMethod(CADisplayLink.class, @selector(setPreferredFrameRateRange:));
            if (Hardware >= 120 && ValidABI(m)) {
                MSHookMessageEx(CADisplayLink.class, @selector(setPreferredFrameRateRange:),
                    (IMP)SetRange, (IMP *)&OriginalRange);
                HookReady = OriginalRange != NULL;
            }
            int token;
            notify_register_dispatch("com.mowang.ui120.changed", &token, dispatch_get_main_queue(), ^(int t) {
                (void)t; Reload();
                if (!Safe()) Restore();
                if (Probe && !Safe()) { Probe.cancelled = YES; [Probe finish]; }
            });
            notify_register_dispatch("com.apple.springboard.lockstate", &token, dispatch_get_main_queue(), ^(int t) {
                (void)t; if (!Safe()) Restore();
                if (Probe && !Safe()) { Probe.cancelled = YES; [Probe finish]; }
            });
            for (NSNotificationName name in @[NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification]) {
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                    (void)n; if (!Safe()) Restore();
                    if (Probe && !Safe()) { Probe.cancelled = YES; [Probe finish]; }
                }];
            }
            if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
                notify_register_dispatch("com.mowang.ui120.diagnose", &token, dispatch_get_main_queue(), ^(int t) {
                    (void)t; Diagnose();
                });
            }
        });
    }
}
