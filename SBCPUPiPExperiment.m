// Public AVKit VideoCall PiP experiment. SpringBoard-only, opt-in, no screenshots/audio/private hooks.
#import "SBCPUPiPExperiment.h"
#import "SBCPUPiPPolicy.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <unistd.h>

static NSString * const SBCPUPiPPrefsDomain = @"com.yourname.sbcpufloating";
static NSString * const SBCPUPiPEnabledKey = @"pipVideoCallExperimentEnabled";
static NSString * const SBCPUPrefsChanged = @"com.yourname.sbcpufloating/settingsChanged";
static UIWindow *(^HostWindow)(void);
static BOOL (^HostLocked)(void);
static NSString *Session;

static BOOL ExperimentEnabled(void) {
    CFPreferencesSynchronize((__bridge CFStringRef)SBCPUPiPPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef value = CFPreferencesCopyValue((__bridge CFStringRef)SBCPUPiPEnabledKey,
        (__bridge CFStringRef)SBCPUPiPPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL enabled = value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    return enabled;
}

static void Publish(PiPState state, NSString *message) {
    NSCAssert(NSThread.isMainThread, @"PiP main thread only");
    NSDictionary *status = @{ @"pid": @(getpid()), @"session": Session ?: @"",
        @"phase": @(state.phase), @"generation": @(state.generation),
        @"active": @(state.phase == PIPActive), @"enabled": @(ExperimentEnabled()),
        @"message": message ?: @"", @"updated": @([NSDate date].timeIntervalSince1970) };
    [status writeToFile:SBCPUPiPStatusPath atomically:YES];
    notify_post(SBCPUPiPChanged);
    NSLog(@"[SBCPUPiP] %@", status);
}

API_AVAILABLE(ios(15.0))
@interface SBCPUPiPManager : NSObject <AVPictureInPictureControllerDelegate> {
    PiPState _state;
    uint64_t _startGeneration;
    CVPixelBufferPoolRef _pool;
    BOOL _observingPossible;
    NSUInteger _frame;
}
@property(nonatomic,strong) AVPictureInPictureController *pip;
@property(nonatomic,strong) AVPictureInPictureVideoCallViewController *content;
@property(nonatomic,strong) AVSampleBufferDisplayLayer *video;
@property(nonatomic,strong) UIView *source;
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic,copy) NSString *message;
- (void)start;
- (void)stop:(NSString *)reason;
- (void)preferenceChanged;
- (void)publishQuery;
@end

@implementation SBCPUPiPManager
- (instancetype)init {
    if ((self = [super init])) _state = (PiPState){PIPOff, 0};
    return self;
}
- (void)setStatus:(NSString *)status {
    self.message = status;
    Publish(_state, status);
}
- (BOOL)hostValid {
    UIWindow *window = HostWindow ? HostWindow() : nil;
    BOOL locked = HostLocked ? HostLocked() : YES;
    return !locked && window && !window.hidden && window.alpha > 0 && window.rootViewController &&
        !CGRectIsEmpty(window.bounds) && window.windowScene &&
        window.windowScene.activationState != UISceneActivationStateUnattached;
}
- (void)stopProduction {
    [self.link invalidate];
    self.link = nil;
    [self.video flushAndRemoveImage];
    if (_pool) { CVPixelBufferPoolRelease(_pool); _pool = NULL; }
}
- (void)cleanup {
    [self stopProduction];
    if (_observingPossible && self.pip) {
        [self.pip removeObserver:self forKeyPath:@"pictureInPicturePossible"];
        _observingPossible = NO;
    }
    self.pip.delegate = nil;
    self.pip.contentSource = nil;
    self.pip = nil;
    [self.source removeFromSuperview];
    self.source = nil;
    [self.video removeFromSuperlayer];
    self.video = nil;
    self.content = nil;
}
- (void)fail:(NSString *)reason {
    ++_state.generation;
    _state.phase = PIPFailed;
    [self cleanup];
    [self setStatus:reason];
}
- (void)start {
    if (!ExperimentEnabled()) {
        if (_state.phase != PIPOff) [self stop:@"实验开关已关闭"];
        else [self setStatus:@"未启动：实验开关关闭（默认关闭）"];
        return;
    }
    if (@available(iOS 15.0, *)) {
        // Continue with the public VideoCall content-source API.
    } else {
        [self fail:@"启动拒绝：VideoCall PiP 需要 iOS 15 或更高版本"];
        return;
    }
    if (!PiPBegin(&_state)) { [self setStatus:@"已有 PiP 实验请求进行中"]; return; }
    if (![self hostValid]) {
        [self fail:(HostLocked && HostLocked()) ? @"启动拒绝：设备已锁定" : @"启动拒绝：宿主窗口不可见或场景未连接"];
        return;
    }
    if (![AVPictureInPictureController isPictureInPictureSupported]) { [self fail:@"启动拒绝：设备不支持公开 PiP"]; return; }

    UIWindow *window = HostWindow();
    self.source = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 120, 68)];
    self.source.backgroundColor = UIColor.darkGrayColor;
    UILabel *label = [[UILabel alloc] initWithFrame:self.source.bounds];
    label.text = @"PiP 实验 · 60";
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:13];
    [self.source addSubview:label];
    [window.rootViewController.view addSubview:self.source];

    self.content = [AVPictureInPictureVideoCallViewController new];
    self.content.preferredContentSize = CGSizeMake(160, 90);
    self.video = [AVSampleBufferDisplayLayer layer];
    self.video.frame = CGRectMake(0, 0, 160, 90);
    self.video.videoGravity = AVLayerVideoGravityResizeAspect;
    self.content.view.frame = CGRectMake(0, 0, 160, 90);
    [self.content.view.layer addSublayer:self.video];
    NSDictionary *attributes = @{ (id)kCVPixelBufferWidthKey: @160, (id)kCVPixelBufferHeightKey: @90,
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{} };
    if (CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)attributes, &_pool) != kCVReturnSuccess) {
        [self fail:@"启动失败：无法创建帧池"];
        return;
    }
    AVPictureInPictureControllerContentSource *source = [[AVPictureInPictureControllerContentSource alloc]
        initWithActiveVideoCallSourceView:self.source contentViewController:self.content];
    self.pip = [[AVPictureInPictureController alloc] initWithContentSource:source];
    if (!self.pip) { [self fail:@"启动失败：无法创建公开 PiP 控制器"]; return; }
    self.pip.delegate = self;
    self.pip.canStartPictureInPictureAutomaticallyFromInline = NO;
    _startGeneration = _state.generation;
    [self.pip addObserver:self forKeyPath:@"pictureInPicturePossible" options:NSKeyValueObservingOptionNew context:NULL];
    _observingPossible = YES;
    [self setStatus:@"准备中：等待系统允许 PiP（最多 5 秒）"];
    [self attemptStart];
    uint64_t generation = _state.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self->_state.generation == generation && self->_state.phase == PIPPreparing)
            [self fail:@"启动失败：5 秒内 PiP possible 未成立"];
    });
}
- (void)attemptStart {
    if (_state.phase != PIPPreparing || !self.pip.pictureInPicturePossible) return;
    if (![self hostValid] || !self.source.window) { [self stop:@"启动前窗口失效或设备锁定"]; return; }
    if (!PiPStart(&_state, _startGeneration)) return;
    [self setStatus:@"启动请求已发送，等待 didStart（最多 5 秒）"];
    [self.pip startPictureInPicture];
    uint64_t generation = _state.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self->_state.generation == generation && self->_state.phase == PIPStarting)
            [self stop:@"启动超时：未收到 didStart"];
    });
}
- (void)produceFrame {
    if (!_pool || !self.video) return;
    CVPixelBufferRef pixel = NULL;
    if (CVPixelBufferPoolCreatePixelBuffer(NULL, _pool, &pixel) != kCVReturnSuccess || !pixel) return;
    CVPixelBufferLockBaseAddress(pixel, 0);
    memset(CVPixelBufferGetBaseAddress(pixel), (uint8_t)(_frame++ & 0xff), CVPixelBufferGetDataSize(pixel));
    CVPixelBufferUnlockBaseAddress(pixel, 0);
    CMSampleTimingInfo timing = { .duration = CMTimeMake(1, 60),
        .presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock()), .decodeTimeStamp = kCMTimeInvalid };
    CMVideoFormatDescriptionRef format = NULL;
    CMSampleBufferRef sample = NULL;
    OSStatus formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixel, &format);
    OSStatus sampleStatus = formatStatus == noErr ? CMSampleBufferCreateForImageBuffer(NULL, pixel, true, NULL, NULL, format, &timing, &sample) : formatStatus;
    if (sampleStatus == noErr && sample) {
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, true);
        if (attachments && CFArrayGetCount(attachments))
            CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0), kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        [self.video enqueueSampleBuffer:sample];
    }
    if (sample) CFRelease(sample);
    if (format) CFRelease(format);
    CFRelease(pixel);
}
- (void)displayTick:(CADisplayLink *)link {
    (void)link;
    if (_state.phase != PIPActive) return;
    if (![self hostValid] || !self.source.window) { [self stop:@"已停止：锁屏或宿主窗口失效"]; return; }
    [self produceFrame];
}
- (void)stop:(NSString *)reason {
    if (_state.phase == PIPStopping) { [self setStatus:reason ?: @"停止请求处理中"]; return; }
    BOOL pending = PiPStop(&_state);
    [self stopProduction];
    if (!pending) {
        [self cleanup];
        [self setStatus:reason ?: @"已停止"];
        return;
    }
    AVPictureInPictureController *controller = self.pip;
    [self setStatus:reason ?: @"停止请求已发送"];
    [controller stopPictureInPicture];
    uint64_t generation = _state.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self->_state.generation == generation && self->_state.phase == PIPStopping) {
            PiPStopTimeout(&self->_state);
            [self cleanup];
            [self setStatus:@"停止未确认：系统未回调 didStop"];
        }
    });
}
- (void)preferenceChanged {
    if (!ExperimentEnabled()) [self stop:@"已停止：实验开关关闭"];
    else if (_state.phase == PIPOff || _state.phase == PIPFailed) [self setStatus:@"已启用，等待用户点“启动 PiP”"];
}
- (void)publishQuery { Publish(_state, self.message ?: @"状态查询"); }
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    (void)keyPath; (void)change; (void)context;
    if (object == self.pip) dispatch_async(dispatch_get_main_queue(), ^{ [self attemptStart]; });
}
- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)controller {
    if (controller != self.pip) return;
    if (PiPDidStart(&_state, _startGeneration)) {
        [self setStatus:@"已激活（公开 AVKit 回调确认；60fps 实验源，未宣称 120）"];
        self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayTick:)];
        self.link.preferredFramesPerSecond = 60;
        [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller {
    if (controller != self.pip) return;
    if (_state.phase == PIPStopping || _state.phase == PIPActive) {
        ++_state.generation;
        _state.phase = PIPOff;
        [self cleanup];
        [self setStatus:@"已停止（公开 AVKit 回调确认）"];
    }
}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller failedToStartPictureInPictureWithError:(NSError *)error {
    if (controller != self.pip || (_state.phase != PIPPreparing && _state.phase != PIPStarting)) return;
    [self fail:[NSString stringWithFormat:@"启动失败：%@", error.localizedDescription ?: @"系统拒绝"]];
}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completion {
    (void)controller;
    if (completion) completion(YES);
}
@end

static SBCPUPiPManager *Manager API_AVAILABLE(ios(15.0));
static int PiPTokens[4];

void SBCPUPiPInstall(UIWindow *(^windowProvider)(void), BOOL (^lockedProvider)(void)) API_AVAILABLE(ios(15.0));
void SBCPUPiPInstall(UIWindow *(^windowProvider)(void), BOOL (^lockedProvider)(void)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SBCPUPiPInstall(windowProvider, lockedProvider); });
        return;
    }
    if (Manager) return;
    HostWindow = [windowProvider copy];
    HostLocked = [lockedProvider copy];
    Session = NSUUID.UUID.UUIDString;
    Manager = (SBCPUPiPManager *)[SBCPUPiPManager new];
    NSArray<NSString *> *names = @[[NSString stringWithUTF8String:SBCPUPiPStartRequest], [NSString stringWithUTF8String:SBCPUPiPStopRequest], [NSString stringWithUTF8String:SBCPUPiPQuery], SBCPUPrefsChanged];
    [names enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, BOOL *stop) {
        (void)stop;
        notify_register_dispatch(name.UTF8String, &PiPTokens[index], dispatch_get_main_queue(), ^(int token) {
            (void)token;
            if ([name isEqualToString:@"com.sbcpu.pip-experiment.start"]) [Manager start];
            else if ([name isEqualToString:@"com.sbcpu.pip-experiment.stop"]) [Manager stop:@"收到停止请求"];
            else if ([name isEqualToString:@"com.yourname.sbcpufloating/settingsChanged"]) [Manager preferenceChanged];
            else [Manager publishQuery];
        });
    }];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationProtectedDataWillBecomeUnavailable object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { [Manager stop:@"已停止：设备锁定"]; }];
    [center addObserverForName:UIWindowDidBecomeHiddenNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { if (note.object == Manager.source.window) [Manager stop:@"已停止：宿主窗口隐藏"]; }];
    [center addObserverForName:UISceneDidDisconnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { if (note.object == Manager.source.window.windowScene) [Manager stop:@"已停止：宿主场景断开"]; }];
    [Manager preferenceChanged];
}

void SBCPUPiPStop(NSString *reason) API_AVAILABLE(ios(15.0));
void SBCPUPiPStop(NSString *reason) {
    dispatch_async(dispatch_get_main_queue(), ^{ [Manager stop:reason ?: @"宿主清理"]; });
}

__attribute__((constructor)) static void SBCPUPiPConstructor(void) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 15.0, *)) {
            SBCPUPiPInstall(^UIWindow *{
            for (UIWindow *window in UIApplication.sharedApplication.windows)
                if (!window.hidden && window.rootViewController && window.windowScene.activationState != UISceneActivationStateUnattached) return window;
            return nil;
            }, ^BOOL{ return !UIApplication.sharedApplication.protectedDataAvailable; });
        }
    });
}
