#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#include <string.h>
#define SBCPU_DYNAMIC_TEST 1
typedef struct { float minimum, maximum, preferred; } CAFrameRateRange;
static CAFrameRateRange CAFrameRateRangeMake(float a,float b,float c) { return (CAFrameRateRange){a,b,c}; }
@interface CADisplayLink : NSObject
@property(nonatomic) CAFrameRateRange preferredFrameRateRange;
@end
@implementation CADisplayLink
@end
@interface CADynamicFrameRateSource : CADisplayLink
@property(nonatomic,getter=isPaused) BOOL paused;
@property(nonatomic) unsigned reasonCalls;
- (void)setHighFrameRateReasons:(const unsigned *)reasons count:(unsigned)count;
@end
@implementation CADynamicFrameRateSource
- (void)setPreferredFrameRateRange:(CAFrameRateRange)r { [super setPreferredFrameRateRange:r]; }
- (void)setHighFrameRateReasons:(const unsigned *)reasons count:(unsigned)count { (void)reasons; self.reasonCalls += count; }
@end
static void MSHookMessageEx(Class c, SEL sel, IMP replacement, IMP *original) {
    Method m = class_getInstanceMethod(c,sel);
    *original = method_setImplementation(m,replacement);
}
#import "../SBCPUDynamicRangeHooks.h"
static NSString *Guard = @"";
static void Request(CADisplayLink *s, float a,float b,float c) { s.preferredFrameRateRange = CAFrameRateRangeMake(a,b,c); }
int main(void) {
    @autoreleasepool {
        assert(SBCPUDynamicABI(CADynamicFrameRateSource.class,@selector(setPreferredFrameRateRange:)));
        assert(!SBCPUDynamicABI(CADynamicFrameRateSource.class,@selector(setPaused:)));
        SBCPUInstallDynamicHooks(YES,^NSString *{ return Guard; });
        assert(SBCPUDynamicReady && SBCPULinkReady);
        CADynamicFrameRateSource *source = [CADynamicFrameRateSource new];
        Request(source,30,60,60);
        assert(source.preferredFrameRateRange.minimum == 120);
        NSDictionary *d = SBCPUDynamicSnapshot();
        assert([d[@"counters"][@"dynamic.changedRanges"] intValue] == 1);
        assert([d[@"counters"][@"displayLink.calls"] intValue] == 1); // nested public setter is not suppressed
        assert([d[@"pendingWeakObjects"] intValue] == 1);
        source.paused = YES; assert(source.isPaused == YES || source.paused == YES);
        source.paused = NO; assert(!source.paused);
        unsigned reasons[2]={7,9}; [source setHighFrameRateReasons:reasons count:2];
        assert(source.reasonCalls == 2);
        Request(source,0,0,0); assert(source.preferredFrameRateRange.maximum == 0);
        assert([SBCPUDynamicSnapshot()[@"pendingWeakObjects"] intValue] == 0);
        Request(source,24,80,60);
        Guard = @"关闭/锁屏/温控";
        // Deferred safe rollback: next EXTERNAL request is forwarded as-is.
        Request(source,30,60,30); assert(source.preferredFrameRateRange.preferred == 30);
        assert([SBCPUDynamicSnapshot()[@"counters"][@"supersededByExternalRequest"] intValue] >= 1);
        Guard = @"";
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
            assert(!NSThread.isMainThread);
            Request(source,20,60,40); assert(source.preferredFrameRateRange.preferred == 40);
            dispatch_semaphore_signal(finished);
        });
        assert(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0);
        assert([SBCPUDynamicSnapshot()[@"counters"][@"offMainPassThrough"] intValue] >= 1);
        __weak CADisplayLink *weak;
        @autoreleasepool { CADisplayLink *temporary=[CADisplayLink new]; weak=temporary; Request(temporary,30,60,60); }
        assert(!weak); // plugin records do not extend host lifetime
        assert([SBCPUDynamicSnapshot()[@"pendingWeakObjects"] intValue] == 0);
        puts("PASS production dynamic hooks: ABI, nested forwarding, real change, defaults, pause/reason, caller-thread, deferred supersession, weak lifetime");
    }
    return 0;
}
