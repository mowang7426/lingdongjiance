#import <objc/runtime.h>
// Public UIKit intervention only. Never retains the system window.
static char SBCPUTextWindowLifetimeKey;
@interface SBCPUTextWindowLifetime : NSObject
@property(nonatomic, copy) void (^ended)(void);
@end
@implementation SBCPUTextWindowLifetime
- (void)dealloc { if (_ended) _ended(); }
@end
@interface SBCPUHiddenTextContainer : UIView
@property(nonatomic, copy) void (^detached)(void);
@end
@implementation SBCPUHiddenTextContainer
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window && self.detached) self.detached();
}
@end

@interface SBCPUHiddenTextExperiment : NSObject
@property(nonatomic, strong) SBCPUHiddenTextContainer *container;
@property(nonatomic, weak) UIWindow *owner;
@property(nonatomic) BOOL creating, attempted, initialized;
@property(nonatomic) NSUInteger createdCount;
@property(nonatomic, copy) NSString *status, *windowClass, *guard;
- (void)updateEnabled:(BOOL)enabled guard:(NSString *)guard;
- (NSDictionary *)snapshot;
@end
@implementation SBCPUHiddenTextExperiment
- (void)removeWithStatus:(NSString *)status {
    // Clear callback before removeFromSuperview: didMoveToWindow can reenter.
    self.container.detached = nil;
    UIWindow *window = self.owner;
    SBCPUTextWindowLifetime *lifetime = objc_getAssociatedObject(window, &SBCPUTextWindowLifetimeKey);
    lifetime.ended = nil;
    if (window) objc_setAssociatedObject(window, &SBCPUTextWindowLifetimeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.container removeFromSuperview];
    self.container = nil; self.owner = nil; self.status = status;
}
- (void)updateEnabled:(BOOL)enabled guard:(NSString *)guard {
    NSAssert(NSThread.isMainThread, @"UIKit experiment must run on main thread");
    if (self.creating) return;
    self.guard = guard ?: @"";
    if (!enabled || self.guard.length) {
        [self removeWithStatus:self.initialized ? @"已移除；初始化副作用未知，注销后再测基线" : @"未创建/保护拒绝"];
        return;
    }
    if (self.container) {
        if (!self.owner || self.owner.hidden || self.container.window != self.owner)
            [self removeWithStatus:@"window隐藏/失效；已释放，需注销重试"];
        return;
    }
    if (self.attempted) { self.status = @"本进程已尝试一次，需注销重试"; return; }
    // Read-only identity matching, no private selectors or init hooks.
    Class statusClass = NSClassFromString(@"UIStatusBarWindow");
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *app = UIApplication.sharedApplication;
    for (UIWindow *w in app.windows) if (![windows containsObject:w]) [windows addObject:w];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows)
                    if (![windows containsObject:w]) [windows addObject:w];
            }
        }
    }
    UIWindow *target = nil;
    for (UIWindow *w in windows) {
        if (statusClass && [w isKindOfClass:statusClass] && !w.hidden) { target = w; break; }
    }
    if (!target) { self.status = @"FAIL：未找到可验证现有UIStatusBarWindow；未创建UITextView，无替代浮窗"; return; }
    self.creating = YES; self.attempted = YES;
    self.windowClass = NSStringFromClass(target.class);
    @try {
        SBCPUHiddenTextContainer *container = [[SBCPUHiddenTextContainer alloc] initWithFrame:CGRectZero];
        container.hidden = YES; container.userInteractionEnabled = NO;
        // Mark before init: even a thrown initializer could have global effects.
        self.initialized = YES;
        UITextView *text = [[UITextView alloc] initWithFrame:CGRectZero];
        text.hidden = YES;
        if (text) self.createdCount++;
        if (container && text) {
            self.container = container;
            [container addSubview:text];
            [target addSubview:container];
            if (container.superview == target && container.window == target) {
                self.owner = target;
                self.status = @"已创建并验证挂载（隐藏CGRectZero UIView+UITextView）";
                __weak SBCPUHiddenTextExperiment *weakSelf = self;
                SBCPUTextWindowLifetime *lifetime = [SBCPUTextWindowLifetime new];
                lifetime.ended = ^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf removeWithStatus:@"window销毁事件；对象释放，需注销重试"];
                    });
                };
                objc_setAssociatedObject(target, &SBCPUTextWindowLifetimeKey, lifetime, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                container.detached = ^{
                    // Event-driven detach/deallocation; no system-window retention.
                    [weakSelf removeWithStatus:@"window脱离/销毁；对象释放，需注销重试"];
                };
            } else {
                [self removeWithStatus:@"FAIL：addSubview后挂载验证失败"];
            }
        } else self.status = @"FAIL：UIKit对象初始化失败";
    } @catch (NSException *exception) {
        (void)exception; [self removeWithStatus:@"FAIL：UIKit初始化/挂载异常；需注销"];
    } @finally { self.creating = NO; }
}
- (NSDictionary *)snapshot {
    return @{@"status":self.status ?: @"未启动", @"guard":self.guard ?: @"未知",
        @"createdCount":@(self.createdCount), @"initializationAttempted":@(self.initialized),
        @"mounted":@(self.container && self.owner && self.container.window == self.owner),
        @"windowClass":self.windowClass ?: @"none", @"mode":@"existing UIStatusBarWindow only; no fallback",
        @"rollback":@"remove/release does not guarantee undoing process-global UIKit initialization; respring required"};
}
@end
