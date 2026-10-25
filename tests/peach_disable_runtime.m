// macOS host fixture: executes the production close handlers and installed
// admission IMPs with UIKit-shaped substitutes, never claims device coverage.
#define main SBCPUPeachCapacityFixtureMain
#import "peach_capacity_runtime.m"
#undef main
#import <CoreFoundation/CoreFoundation.h>
typedef NSInteger UIGestureRecognizerState;
enum { UIGestureRecognizerStateBegan = 1, UIGestureRecognizerStateChanged = 2 };
@interface UIGestureRecognizer : NSObject
@property UIGestureRecognizerState state;
@end
@implementation UIGestureRecognizer @end
@interface UIView : NSObject
- (NSArray *)gestureRecognizers;
@end
@implementation UIView
- (NSArray *)gestureRecognizers { return @[]; }
@end
@interface SBIconListView (SBCPUPeachFixtureGestures)
- (NSArray *)gestureRecognizers;
@end
@implementation SBIconListView (SBCPUPeachFixtureGestures)
- (NSArray *)gestureRecognizers { return @[]; }
@end
@interface UIScrollView : UIView
@property BOOL dragging, decelerating, tracking;
@end
@implementation UIScrollView @end
static UIScrollView *SBCPUPeachDockScrollView(id list) { (void)list; return nil; }
static BOOL editing, editingKnown = YES;
static BOOL SBCPUPeachDockDockReadEditing(id list, BOOL *out) {
    (void)list; *out = editing; return editingKnown;
}
typedef NSUInteger UIDropOperation;
enum { UIDropOperationCancel = 0, SBCPUPeachFixtureMove = 3 };
@interface UIDropProposal : NSObject
@property UIDropOperation operation;
- (instancetype)initWithDropOperation:(UIDropOperation)operation;
@end
@implementation UIDropProposal
- (instancetype)initWithDropOperation:(UIDropOperation)operation {
    if ((self = [super init])) _operation = operation; return self;
}
@end
static unsigned performCount;
@interface SBIconDragManager : NSObject
- (_Bool)iconViewCanBeginDrags:(id)view;
- (void)iconViewWillBeginDrag:(id)view session:(id)session;
- (void)iconView:(id)view didEndDragSession:(id)session withOperation:(unsigned long long)operation;
- (_Bool)iconListView:(id)list canHandleIconDropSession:(id)session;
- (id)iconListView:(id)list iconDropSessionDidUpdate:(id)session;
- (void)iconListView:(id)list performIconDrop:(id)session;
@end
@implementation SBIconDragManager
- (_Bool)iconViewCanBeginDrags:(id)view { (void)view; return YES; }
- (void)iconViewWillBeginDrag:(id)view session:(id)session { (void)view; (void)session; }
- (void)iconView:(id)view didEndDragSession:(id)session withOperation:(unsigned long long)operation { (void)view; (void)session; (void)operation; }
- (_Bool)iconListView:(id)list canHandleIconDropSession:(id)session { (void)list; (void)session; return YES; }
- (id)iconListView:(id)list iconDropSessionDidUpdate:(id)session {
    (void)list; (void)session;
    return [[UIDropProposal alloc] initWithDropOperation:SBCPUPeachFixtureMove];
}
- (void)iconListView:(id)list performIconDrop:(id)session { (void)list; (void)session; ++performCount; }
@end
// Disk I/O is a controllable boundary; production state machine/Hook code below
// is included verbatim. Never write the developer's real preference domain.
static int persistedState; // enabled=0, disabled=1, sync failure=-1
static Boolean SBCPUPeachFixtureSync(void) { return persistedState >= 0; }
static CFPropertyListRef SBCPUPeachFixtureCopy(void) {
    return CFRetain(persistedState == 1 ? kCFBooleanFalse : kCFBooleanTrue);
}
#define CFPreferencesSynchronize(a,b,c) SBCPUPeachFixtureSync()
#define CFPreferencesCopyValue(a,b,c,d) SBCPUPeachFixtureCopy()
#import "../PeachDock/SBCPUPeachDockDisable.h"
#undef CFPreferencesSynchronize
#undef CFPreferencesCopyValue
static NSString *Request(NSString *phase, NSString *nonce) {
    return SBCPUPeachDockDisableHandle(@{@"phase":phase,@"nonce":nonce})[@"status"];
}
static void Expect(NSString *phase, NSString *nonce, NSString *status) {
    assert([Request(phase,nonce) isEqual:status]);
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc == 3 && !strcmp(argv[1], "--ipc-prepare")) {
        NSDictionary *response = SBCPUPeachDockDisableMessage(@"prepare", [NSString stringWithUTF8String:argv[2]]);
        return [response[@"status"] isEqual:@"prepared"] ? 0 : 2;
    }
    assert(SBCPUPeachCapacityFixtureMain() == 0);
    assert(SBCPUPeachDockDisableReady());
    assert(SBCPUPeachDockInstallDisable());
    NSString *nonce = NSUUID.UUID.UUIDString;
    Expect(@"prepare",nonce,@"unknown");
    SBDockIconListView *dock = [SBDockIconListView new];
    dock.model = [SBIconListModel new];
    dock.model.numberOfIcons = 5;
    Expect(@"prepare",nonce,@"overflow");
    dock.model.numberOfIcons = 4;
    editing = YES; Expect(@"prepare",nonce,@"busy"); editing = NO;
    editingKnown = NO; Expect(@"prepare",nonce,@"busy"); editingKnown = YES;
    SBIconDragManager *manager = [SBIconDragManager new];
    NSObject *session = [NSObject new];
    [manager iconViewWillBeginDrag:nil session:session];
    Expect(@"prepare",nonce,@"busy");
    [manager iconView:nil didEndDragSession:session withOperation:0];
    // A fresh executable has no access to this process's bound count globals.
    // It must receive a real port response from the production main-runloop callback.
    NSTask *client = [NSTask new];
    client.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
    client.arguments = @[@"--ipc-prepare", nonce];
    NSError *launchError = nil;
    assert([client launchAndReturnError:&launchError] && !launchError);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (client.running && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    assert(!client.running && client.terminationStatus == 0);
    assert(SBCPUPeachDockAdmissionLocked()); // true before caller persists false
    assert(![manager iconViewCanBeginDrags:nil]);
    assert(![manager iconListView:dock canHandleIconDropSession:nil]);
    assert([(UIDropProposal *)[manager iconListView:dock iconDropSessionDidUpdate:nil] operation] == UIDropOperationCancel);
    [manager iconListView:dock performIconDrop:nil]; assert(performCount == 0);
    SBIconListView *home = [SBIconListView new];
    assert([manager iconListView:home canHandleIconDropSession:nil]);
    [manager iconListView:home performIconDrop:nil]; assert(performCount == 1);
    Expect(@"commit",nonce,@"write-not-observed");
    persistedState = -1; Expect(@"cancel",nonce,@"locked");
    assert(SBCPUPeachDockAdmissionLocked());
    persistedState = 0; Expect(@"cancel",nonce,@"cancelled");
    assert(!SBCPUPeachDockAdmissionLocked());
    assert([manager iconViewCanBeginDrags:nil]);
    Expect(@"prepare",nonce,@"cancelled"); // late prepare after client timeout
    nonce = NSUUID.UUID.UUIDString;
    Expect(@"prepare",nonce,@"prepared");
    Expect(@"cancel",NSUUID.UUID.UUIDString,@"cancelled");
    assert(SBCPUPeachDockAdmissionLocked()); // wrong nonce cannot release owner
    persistedState = 1;
    Expect(@"commit",nonce,@"committed");
    Expect(@"cancel",nonce,@"committed");
    assert(SBCPUPeachDockAdmissionLocked());
    assert(![manager iconListView:dock canHandleIconDropSession:nil]);
    [manager iconListView:dock performIconDrop:nil]; assert(performCount == 1);
    puts("PASS: production nonce state machine and admission hooks; unknown/overflow/busy rejection; write/cancel/commit lock ordering; late prepare and post-commit drag rejection");
} return 0; }
