// macOS host contract test: clang -fobjc-arc -framework Foundation
// tests/peach_capacity_runtime.m -o /tmp/peach-capacity && /tmp/peach-capacity
// Executes the production hook installer and replacements. Not a SpringBoard
// drag/restore validation and does not claim getter callers match Apple's code.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <assert.h>

@interface SBIconListModel : NSObject
@property unsigned long long numberOfIcons;
- (unsigned long long)maxNumberOfIcons;
@end
@implementation SBIconListModel
- (unsigned long long)maxNumberOfIcons { return 4; }
@end
@interface SBIconListView : NSObject
@property(nonatomic,strong) SBIconListModel *model;
- (unsigned long long)maximumIconCount;
@end
@implementation SBIconListView
- (unsigned long long)maximumIconCount { return self.model.maxNumberOfIcons; }
@end
@interface SBDockIconListView : SBIconListView @end
@implementation SBDockIconListView @end
@interface SBCPUPeachDockWeakOwner : NSObject
@property(nonatomic,weak) SBDockIconListView *list;
@end
@implementation SBCPUPeachDockWeakOwner @end
static const NSUInteger SBCPUPeachDockMaximumDockIcons = 100;
static unsigned installs;
static void MSHookMessageEx(Class cls, SEL sel, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls, sel);
    assert(method);
    *original = method_getImplementation(method);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(cls, sel), replacement);
    installs++;
}
#import "../PeachDock/SBCPUPeachDockCapacity.h"

int main(void) { @autoreleasepool {
    unsigned long long count = 999;
    assert(!SBCPUPeachDockReadBoundCount(&count) && count == 999);
    Class badModel = objc_allocateClassPair(NSObject.class, "SBCPUPeachBadModel", 0);
    objc_registerClassPair(badModel);
    SBCPUPeachDockInstallCapacity(SBDockIconListView.class, badModel);
    assert(installs == 0); // missing ABI prevents the entire capacity group
    assert(SBCPUPeachDockCapacityReady(SBDockIconListView.class, SBIconListModel.class));
    assert(!SBCPUPeachDockCapacityMethod(SBDockIconListView.class, "setModel:", "v@:Q"));
    assert(!SBCPUPeachDockCapacityMethod(SBIconListModel.class, "numberOfIcons", "I@:"));
    SBCPUPeachDockInstallCapacity(SBDockIconListView.class, SBIconListModel.class);
    assert(installs == 4);
    SBIconListModel *normal = [SBIconListModel new];
    SBIconListModel *dockModel = [SBIconListModel new];
    SBIconListView *home = [SBIconListView new]; home.model = normal;
    assert(normal.maxNumberOfIcons == 4 && home.maximumIconCount == 4);
    assert(dockModel.maxNumberOfIcons == 4); // unbound does not expand
    SBDockIconListView *dock = [SBDockIconListView new]; dock.model = dockModel;
    assert(dock.model == dockModel);
    assert(dockModel.maxNumberOfIcons == 100 && dock.maximumIconCount == 100);
    assert(normal.maxNumberOfIcons == 4 && home.maximumIconCount == 4);
    dockModel.numberOfIcons = 9;
    assert(SBCPUPeachDockReadBoundCount(&count) && count == 9);
    dockModel.numberOfIcons = 4;
    assert(SBCPUPeachDockReadBoundCount(&count) && count == 4);
    SBIconListModel *replacement = [SBIconListModel new]; dock.model = replacement;
    assert(dockModel.maxNumberOfIcons == 4); // stale association loses ownership
    assert(replacement.maxNumberOfIcons == 100);
    dock.model = nil;
    assert(replacement.maxNumberOfIcons == 4);
    assert(!SBCPUPeachDockReadBoundCount(&count));
    dock = nil;
    assert(!SBCPUPeachDockReadBoundCount(&count));
    puts("PASS: actual capacity installer, inherited chaining, Dock identity, non-Dock isolation, model replacement, nil/unobserved recovery refusal");
} return 0; }
