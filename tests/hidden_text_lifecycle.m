// Native state-machine test with public UIKit-shaped doubles, NOT a device test.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
@class UIWindow;
@interface UIView : NSObject
@property(nonatomic) BOOL hidden, userInteractionEnabled;
@property(nonatomic, weak) UIView *superview;
@property(nonatomic, readonly) UIWindow *window;
@property(nonatomic, strong) NSMutableArray *children;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)v;
- (void)removeFromSuperview;
- (void)didMoveToWindow;
@end
@interface UIWindow : UIView @end
@implementation UIView
- (instancetype)initWithFrame:(CGRect)frame { (void)frame; if ((self=[super init])) _children=[NSMutableArray new]; return self; }
- (UIWindow *)window { return [self isKindOfClass:UIWindow.class] ? (UIWindow *)self : self.superview.window; }
- (void)addSubview:(UIView *)v { [v removeFromSuperview]; [self.children addObject:v]; v.superview=self; [v didMoveToWindow]; }
- (void)removeFromSuperview { UIView *parent=self.superview; self.superview=nil; [parent.children removeObject:self]; [self didMoveToWindow]; }
- (void)didMoveToWindow {}
@end
@implementation UIWindow @end
@interface UIStatusBarWindow : UIWindow @end
@implementation UIStatusBarWindow @end
static NSUInteger textInitializations;
static void (^onTextInit)(void);
@interface UITextView : UIView @end
@implementation UITextView
- (instancetype)initWithFrame:(CGRect)frame { textInitializations++; if (onTextInit) onTextInit(); return [super initWithFrame:frame]; }
@end
@interface UIScene : NSObject @end
@implementation UIScene @end
@interface UIWindowScene : UIScene
@property(nonatomic, strong) NSArray *windows;
@end
@implementation UIWindowScene @end
@interface UIApplication : NSObject
@property(nonatomic, strong) NSArray *windows;
@property(nonatomic, strong) NSSet *connectedScenes;
+ (instancetype)sharedApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if (!app) { app=[self new]; app.windows=@[]; app.connectedScenes=[NSSet new]; } return app; }
@end
#import "../SBCPUHiddenTextExperiment.h"
#define CHECK(c) do { if (!(c)) { NSLog(@"FAIL line %d: %s",__LINE__,#c); exit(1); } } while(0)
int main(void) { @autoreleasepool {
    UIApplication *app=UIApplication.sharedApplication;
    SBCPUHiddenTextExperiment *e=[SBCPUHiddenTextExperiment new];
    [e updateEnabled:NO guard:@"OFF"]; CHECK(textInitializations==0);
    [e updateEnabled:YES guard:@""]; CHECK(textInitializations==0); CHECK([e.status containsString:@"FAIL"]);
    UIWindow *wrong=[[UIWindow alloc] initWithFrame:CGRectZero]; app.windows=@[wrong];
    [e updateEnabled:YES guard:@""]; CHECK(textInitializations==0);
    UIStatusBarWindow *w=[[UIStatusBarWindow alloc] initWithFrame:CGRectZero]; w.hidden=YES; app.windows=@[w];
    [e updateEnabled:YES guard:@""]; CHECK(textInitializations==0);
    w.hidden=NO;
    [e updateEnabled:YES guard:@"锁屏/AOD"]; CHECK(textInitializations==0);
    __weak SBCPUHiddenTextExperiment *weak=e;
    onTextInit=^{ [weak updateEnabled:YES guard:@""]; };
    [e updateEnabled:YES guard:@""]; onTextInit=nil;
    CHECK(textInitializations==1); CHECK(e.createdCount==1); CHECK([e.snapshot[@"mounted"] boolValue]);
    CHECK(e.container.hidden); CHECK(e.container.children.count==1); CHECK([e.container.children[0] hidden]);
    [e updateEnabled:YES guard:@""]; CHECK(textInitializations==1);
    __weak UIView *container=e.container; __weak UIView *text=e.container.children[0];
    [e updateEnabled:YES guard:@"低电量"];
    CHECK(!e.container && !e.owner && !container && !text); CHECK(w.children.count==0);
    [e updateEnabled:YES guard:@""]; CHECK(textInitializations==1);
    SBCPUHiddenTextExperiment *e2=[SBCPUHiddenTextExperiment new];
    [e2 updateEnabled:YES guard:@""]; CHECK([e2.snapshot[@"mounted"] boolValue]);
    [e2.container removeFromSuperview]; CHECK(!e2.container && !e2.owner);
    [e2 updateEnabled:YES guard:@""]; CHECK(textInitializations==2);
    SBCPUHiddenTextExperiment *e3=[SBCPUHiddenTextExperiment new];
    [e3 updateEnabled:YES guard:@""]; CHECK([e3.snapshot[@"mounted"] boolValue]);
    w.hidden=YES; [e3 updateEnabled:YES guard:@""]; CHECK(!e3.container);
    CHECK(objc_getAssociatedObject(w,&SBCPUTextWindowLifetimeKey)==nil);
    NSLog(@"PASS native hidden-text lifecycle doubles: missing/hidden/wrong window, guard, reentry, once, detach, remove/release and lifetime cleanup");
} return 0; }
