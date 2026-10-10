#import "SBCPURefreshDiagnostics.h"
#import "SBCPURefreshRequestPolicy.h"
#import <objc/runtime.h>
#import <notify.h>
#import <unistd.h>
#include <string.h>
#include <math.h>
#import <sys/sysctl.h>

static NSString *SBCPURefreshMethodABI(Class cls, SEL sel) {
    Method m = cls ? class_getInstanceMethod(cls,sel) : NULL;
    return m ? [NSString stringWithUTF8String:method_getTypeEncoding(m)] : @"absent";
}
static BOOL SBCPURefreshSetterABI(SEL sel, const char *argument) {
    Method m = class_getInstanceMethod(CADisplayLink.class,sel);
    if (!m) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    return sig.numberOfArguments == 3 && strcmp(sig.methodReturnType,@encode(void)) == 0 &&
        strcmp([sig getArgumentTypeAtIndex:2],argument) == 0;
}

@interface SBCPURefreshRuntime : NSObject {
    CADisplayLink *_link;
    BOOL _enabled, _lockKnown, _locked, _displayKnown, _displayOn, _rangeABI, _fpsABI;
    NSInteger _capability;
    BOOL _hardware120;
    NSString *_model;
    NSString *_reason, *_requestSelector;
    NSMutableDictionary *_audit;
    int _lockToken, _displayToken;
    CFTimeInterval _first, _last;
    NSUInteger _callbacks;
    double _callbackHz, _sampleSeconds;
    CFTimeInterval _sampleAt;
}
+ (instancetype)shared;
- (void)start;
- (void)updateRequest;
- (void)tick:(CADisplayLink *)link;
- (void)writeDiagnostic;
@end

@implementation SBCPURefreshRuntime
+ (instancetype)shared {
    static SBCPURefreshRuntime *runtime;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ runtime = [self new]; });
    return runtime;
}
- (void)readLock {
    uint64_t state = 0;
    _lockKnown = _lockToken >= 0 && notify_get_state(_lockToken,&state) == NOTIFY_STATUS_OK;
    _locked = !_lockKnown || state != 0;
}
- (void)readDisplay {
    uint64_t state = 0;
    _displayKnown = _displayToken >= 0 && notify_get_state(_displayToken,&state) == NOTIFY_STATUS_OK;
    _displayOn = _displayKnown && state != 0;
}
- (void)start {
    _capability = UIScreen.mainScreen.maximumFramesPerSecond; // NEVER hook/fake capability
    char model[128] = {0}; size_t modelSize = sizeof(model)-1;
    if (sysctlbyname("hw.machine",model,&modelSize,NULL,0) != 0) model[0] = 0;
    _model = [NSString stringWithUTF8String:model] ?: @"unknown";
    _hardware120 = SBCPURefreshHardware120(model);
    _fpsABI = SBCPURefreshSetterABI(@selector(setPreferredFramesPerSecond:),@encode(NSInteger));
    _audit = [NSMutableDictionary dictionary];
    _audit[@"CADisplayLink.setPreferredFramesPerSecond:"] = SBCPURefreshMethodABI(CADisplayLink.class,@selector(setPreferredFramesPerSecond:));
    if (@available(iOS 15.0, *)) {
        _rangeABI = SBCPURefreshSetterABI(@selector(setPreferredFrameRateRange:),@encode(CAFrameRateRange));
        _audit[@"CADisplayLink.setPreferredFrameRateRange:"] = SBCPURefreshMethodABI(CADisplayLink.class,@selector(setPreferredFrameRateRange:));
    }
    // Inspect but do NOT install guessed NSInteger hooks on private selectors.
    _audit[@"SBProMotionPolicy.maximumSupportedRefreshRate (not hooked)"] = SBCPURefreshMethodABI(NSClassFromString(@"SBProMotionPolicy"),NSSelectorFromString(@"maximumSupportedRefreshRate"));
    _audit[@"SBDisplayRefreshRateController.maximumRefreshRate (not hooked)"] = SBCPURefreshMethodABI(NSClassFromString(@"SBDisplayRefreshRateController"),NSSelectorFromString(@"maximumRefreshRate"));
    // Read-only discovery of candidate CA policies; signatures are evidence, not permission to invoke.
    for (NSString *selector in @[@"initWithDisplay:", @"setPreferredFrameRateRange:", @"setHighFrameRateReasons:count:"]) {
        NSString *key = [@"CADynamicFrameRateSource." stringByAppendingString:selector];
        _audit[key] = SBCPURefreshMethodABI(NSClassFromString(@"CADynamicFrameRateSource"),NSSelectorFromString(selector));
    }
    _audit[@"CADisplay.setHighFrameRateReason: (not called)"] = SBCPURefreshMethodABI(NSClassFromString(@"CADisplay"),NSSelectorFromString(@"setHighFrameRateReason:"));
    _lockToken = _displayToken = -1;
    int result = notify_register_dispatch("com.apple.springboard.lockstate",&_lockToken,dispatch_get_main_queue(),^(int token) {
        (void)token; [self readLock]; [self updateRequest];
    });
    if (result != NOTIFY_STATUS_OK) _lockToken = -1;
    result = notify_register_dispatch("com.apple.iokit.hid.displayStatus",&_displayToken,dispatch_get_main_queue(),^(int token) {
        (void)token; [self readDisplay]; [self updateRequest];
    });
    if (result != NOTIFY_STATUS_OK) _displayToken = -1;
    [self readLock]; [self readDisplay];
    int prefsToken;
    notify_register_dispatch("com.yourname.sbcpufloating/settingsChanged",&prefsToken,dispatch_get_main_queue(),^(int token) {
        (void)token; self->_enabled = SBCPU120HzEnabled(); [self updateRequest];
    });
    int diagnosticToken;
    notify_register_dispatch(SBCPU_REFRESH_DIAGNOSTIC_REQUEST,&diagnosticToken,dispatch_get_main_queue(),^(int token) {
        (void)token; [self readLock]; [self readDisplay]; [self updateRequest]; [self writeDiagnostic];
    });
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification]) {
        [nc addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            (void)n; [self updateRequest];
        }];
    }
    _enabled = SBCPU120HzEnabled();
    [self updateRequest];
}
- (void)updateRequest {
    const char *reason = SBCPURefreshPauseReason(_enabled,(int)_capability,_rangeABI || _fpsABI,
        _lockKnown,_locked,_displayKnown,_displayOn,NSProcessInfo.processInfo.lowPowerModeEnabled,
        (int)NSProcessInfo.processInfo.thermalState);
    _reason = _enabled && !_hardware120 ? @"未确认真实120Hz硬件型号，安全暂停" : [NSString stringWithUTF8String:reason];
    if (_reason.length) {
        [_link invalidate]; _link = nil;
        _first = _last = 0; _callbacks = 0; _callbackHz = _sampleSeconds = 0; _sampleAt = 0;
        _requestSelector = @"none (paused)";
        return;
    }
    if (!_link) {
        _first = _last = 0; _callbacks = 0; _callbackHz = _sampleSeconds = 0; _sampleAt = 0;
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        // Own link is created/reconfigured immediately on state changes, including
        // prefs changed after boot. Never mutate other components' existing links.
        if (@available(iOS 15.0, *)) {
            if (_rangeABI) {
                _link.preferredFrameRateRange = CAFrameRateRangeMake(120.0f,120.0f,120.0f);
                _requestSelector = @"CADisplayLink.setPreferredFrameRateRange: (public, ABI verified)";
            }
        }
        if (!_rangeABI && _fpsABI) {
            _link.preferredFramesPerSecond = 120;
            _requestSelector = @"CADisplayLink.setPreferredFramesPerSecond: (public, ABI verified)";
        }
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)tick:(CADisplayLink *)link {
    // Pure memory counters: no preferences sync, notifications, file writes or screenshots.
    CFTimeInterval now = link.timestamp;
    if (!isfinite(now) || now <= _last || (_last && now-_last > 0.5)) {
        _first = _last = now; _callbacks = 0; _callbackHz = _sampleSeconds = 0; _sampleAt = 0; return;
    }
    if (!_first) _first = now;
    _last = now;
    _callbacks++;
    if (now-_first >= 2.0) {
        _sampleSeconds = now-_first;
        _sampleAt = CACurrentMediaTime();
        _callbackHz = (_callbacks-1)/_sampleSeconds;
        _first = now; _callbacks = 1;
    }
}
- (void)writeDiagnostic {
    NSString *path = SBCPURefreshDiagnosticPath();
    if (!path) return;
    id gate = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CADisableMinimumFrameDurationOnPhone"];
    NSString *gateStatus = !gate ? @"absent" : ([gate isKindOfClass:NSNumber.class] ? ([gate boolValue] ? @"true" : @"false") : @"invalid type (not a boolean)");
    BOOL fresh = _sampleAt > 0 && CACurrentMediaTime()-_sampleAt <= 5 && _sampleSeconds >= 2;
    NSString *limitation = !_link ? @"请求已暂停，参见暂停原因" : (!fresh ? @"有效采样不足2秒或样本超过5秒，不能判断当前调度结果" : (_callbackHz < 90 ? @"120请求已提交，但本displaylink回调低于90Hz；系统未按请求调度，宿主资格/CA仲裁/主线程负载的具体原因未确认" : @"回调超过90Hz仍不等于面板120Hz，亦非全App资格"));
    NSDictionary *snapshot = @{@"generatedAt":@([NSDate date].timeIntervalSince1970), @"pid":@(getpid()),
        @"loaded":@YES, @"enabled":@(_enabled), @"originalCapability":@(_capability),
        @"hardwareModel":_model ?: @"unknown", @"hardware120":@(_hardware120),
        @"selectorABI":_audit ?: @{}, @"installedHooks":@"none; no UIScreen/private getter spoofing",
        @"requestSelector":_requestSelector ?: @"none", @"requestedHz":@(_link ? 120 : 0),
        @"callbackHz":@(_callbackHz), @"sampleSeconds":@(_sampleSeconds), @"pauseReason":_reason ?: @"初始化中",
        @"sampleFresh":@(fresh), @"sampleAgeSeconds":@(_sampleAt > 0 ? CACurrentMediaTime()-_sampleAt : -1),
        @"hostBundle":NSBundle.mainBundle.bundleIdentifier ?: @"unknown", @"phoneHighFrameRateGate":gateStatus,
        @"limitation":limitation, @"privatePolicy":@"read-only selector audit; no dynamic source/restriction/arbitration override",
        @"lowPowerMode":@(NSProcessInfo.processInfo.lowPowerModeEnabled), @"thermalState":@(NSProcessInfo.processInfo.thermalState),
        @"scope":@"SpringBoard owned displaylink only; callback Hz != panel Hz or game FPS"};
    // Only a user-requested snapshot crosses processes. No per-frame/status polling writes.
    [snapshot writeToFile:path atomically:YES];
}
@end
