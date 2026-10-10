#ifndef SBCPU_DYNAMIC_TEST
#import <substrate.h>
#endif
#import "SBCPUDynamicRangePolicy.h"
#ifdef SBCPU_DYNAMIC_TEST
#define SBCPU_RANGE_API
#else
#define SBCPU_RANGE_API __attribute__((availability(ios,introduced=15.0)))
#endif
/* Only the two range setters are hooked. Pause/reason/init/getters are untouched.
 * No synchronous dispatch or private calls on a guessed owner queue. Main-thread
 * incoming requests alone may be rewritten; all originals run on caller thread.
 * Weak records back up latest EXTERNAL request, not our replacement. There is NO
 * eager private restore: a blocked/new external request supersedes our range.
 * Off-main requests also supersede it. Objects with no next request need respring.
 */
static NSString *(^SBCPUDynamicGuard)(void);
static NSMapTable *SBCPUDynamicRecords;
static NSObject *SBCPUDynamicMutex;
static NSMutableDictionary *SBCPUDynamicCounters;
static NSMutableDictionary *SBCPUDynamicLast;
static BOOL SBCPUDynamicReady, SBCPULinkReady;
static SBCPU_RANGE_API void (*SBCPUOriginalDynamicRange)(id, SEL, CAFrameRateRange);
static SBCPU_RANGE_API void (*SBCPUOriginalLinkRange)(id, SEL, CAFrameRateRange);
static __thread unsigned SBCPUDynamicReentry[2];
static SBCPU_RANGE_API NSArray *SBCPURangeArray(CAFrameRateRange r) {
    // Malformed NaN/Inf must not enter a plist; evidence remains printable.
    return @[[NSString stringWithFormat:@"%.9g",r.minimum],
             [NSString stringWithFormat:@"%.9g",r.maximum],
             [NSString stringWithFormat:@"%.9g",r.preferred]];
}
static void SBCPUCount(NSString *key) {
    SBCPUDynamicCounters[key] = @([SBCPUDynamicCounters[key] unsignedLongLongValue]+1);
}
static SBCPU_RANGE_API void SBCPUInterceptRange(id object, SEL cmd, CAFrameRateRange range, BOOL dynamic,
                               void (*original)(id,SEL,CAFrameRateRange)) {
    unsigned slot = dynamic ? 0 : 1;
    if (SBCPUDynamicReentry[slot]) { original(object,cmd,range); return; }
    BOOL main = NSThread.isMainThread;
    NSString *reason = main ? SBCPUDynamicGuard() : @"非主线程请求：原线程透传，不猜对象队列";
    BOOL eligible = SBCPUDynamicRangeEligible(range.minimum,range.maximum,range.preferred);
    BOOL rewrite = main && !reason.length && eligible;
    CAFrameRateRange output = range;
    NSString *prefix = dynamic ? @"dynamic" : @"displayLink";
    @synchronized (SBCPUDynamicMutex) {
        SBCPUCount([prefix stringByAppendingString:@".calls"]);
        NSDictionary *previous = [SBCPUDynamicRecords objectForKey:object];
        if (rewrite && !previous && SBCPUDynamicRecords.count >= 512) {
            rewrite = NO; reason = @"弱记录达到512上限：透传";
        }
        if (rewrite) {
            output = CAFrameRateRangeMake(120,120,120);
            [SBCPUDynamicRecords setObject:@{@"latestExternal":SBCPURangeArray(range),
                @"kind":prefix, @"pending":@YES} forKey:object];
            SBCPUCount([prefix stringByAppendingString:@".rewrites"]);
            if (range.minimum != 120 || range.maximum != 120 || range.preferred != 120)
                SBCPUCount([prefix stringByAppendingString:@".changedRanges"]);
        } else {
            if ([previous[@"pending"] boolValue]) SBCPUCount(@"supersededByExternalRequest");
            [SBCPUDynamicRecords removeObjectForKey:object];
            SBCPUCount(main ? (eligible ? @"protectedPassThrough" : @"ineligiblePassThrough") : @"offMainPassThrough");
        }
        SBCPUDynamicLast[prefix] = @{@"input":SBCPURangeArray(range), @"output":SBCPURangeArray(output),
            @"rewritten":@(rewrite), @"mainThread":@(main),
            @"guard":reason.length ? reason : (eligible ? @"允许" : @"范围不合格：透传")};
    }
    // Never hold our lock while invoking external code. Preserve invocation count,
    // thread, selector and every non-range lifecycle/reason update.
    ++SBCPUDynamicReentry[slot];
    @try { original(object,cmd,output); }
    @finally { --SBCPUDynamicReentry[slot]; }
}
static SBCPU_RANGE_API void SBCPUHookDynamicRange(id object, SEL cmd, CAFrameRateRange range) {
    SBCPUInterceptRange(object,cmd,range,YES,SBCPUOriginalDynamicRange);
}
static SBCPU_RANGE_API void SBCPUHookLinkRange(id object, SEL cmd, CAFrameRateRange range) {
    SBCPUInterceptRange(object,cmd,range,NO,SBCPUOriginalLinkRange);
}
static SBCPU_RANGE_API BOOL SBCPUDynamicABI(Class cls, SEL selector) {
    Method m = cls ? class_getInstanceMethod(cls,selector) : NULL;
    if (!m || method_getNumberOfArguments(m) != 3) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    return sig && sig.numberOfArguments == 3 &&
        !strcmp(sig.methodReturnType,@encode(void)) &&
        !strcmp([sig getArgumentTypeAtIndex:0],@encode(id)) &&
        !strcmp([sig getArgumentTypeAtIndex:1],@encode(SEL)) &&
        !strcmp([sig getArgumentTypeAtIndex:2],@encode(CAFrameRateRange));
}
static void SBCPUInstallDynamicHooks(BOOL real120, NSString *(^guard)(void)) {
    SBCPUDynamicGuard = [guard copy];
    SBCPUDynamicMutex = [NSObject new];
    SBCPUDynamicRecords = [NSMapTable weakToStrongObjectsMapTable];
    SBCPUDynamicCounters = [NSMutableDictionary dictionary];
    SBCPUDynamicLast = [NSMutableDictionary dictionary];
    if (!real120) return;
    if (@available(iOS 15.0, *)) {
    SEL setter = NSSelectorFromString(@"setPreferredFrameRateRange:");
    Class dynamic = NSClassFromString(@"CADynamicFrameRateSource");
    if (SBCPUDynamicABI(dynamic,setter)) {
        MSHookMessageEx(dynamic,setter,(IMP)SBCPUHookDynamicRange,(IMP *)&SBCPUOriginalDynamicRange);
        SBCPUDynamicReady = SBCPUOriginalDynamicRange != NULL;
    }
    if (SBCPUDynamicABI(CADisplayLink.class,setter)) {
        MSHookMessageEx(CADisplayLink.class,setter,(IMP)SBCPUHookLinkRange,(IMP *)&SBCPUOriginalLinkRange);
        SBCPULinkReady = SBCPUOriginalLinkRange != NULL;
    }
    }
}
static NSDictionary *SBCPUDynamicSnapshot(void) {
    @synchronized (SBCPUDynamicMutex) {
        NSMutableArray *backups = [NSMutableArray array];
        for (id object in SBCPUDynamicRecords) {
            NSDictionary *record = [SBCPUDynamicRecords objectForKey:object];
            if (record) [backups addObject:record]; // no object retained in snapshot
        }
        return @{@"dynamicHookInstalled":@(SBCPUDynamicReady), @"displayLinkHookInstalled":@(SBCPULinkReady),
            @"counters":[SBCPUDynamicCounters copy], @"lastRanges":[SBCPUDynamicLast copy],
            @"pendingWeakObjects":@(backups.count), @"latestExternalBackups":backups,
            @"restorePolicy":@"仅新请求原线程透传/覆盖；不跨线程重放私有range，不承诺即时恢复；关闭后respring清除存量修改",
            @"pauseAndReasons":@"setPaused:/isPaused/reason setters未hook，全部原行为"};
    }
}
