// macOS Foundation fixture executing the production Dock-only hook installer.
// This establishes substitute call ordering, not Apple's iOS 16.2 call graph.
#define main SBCPUPeachCapacityFixtureMain
#import "peach_capacity_runtime.m"
#undef main
@interface SBHIconModel : NSObject
- (unsigned long long)maxIconCountForDock;
- (unsigned long long)maxIconCountForDockForIconStateUnarchiver:(id)unarchiver;
- (unsigned long long)maxIconCountForRoot;
@end
@implementation SBHIconModel
- (unsigned long long)maxIconCountForDock { return 4; }
- (unsigned long long)maxIconCountForDockForIconStateUnarchiver:(id)unarchiver {
    (void)unarchiver; return [self maxIconCountForDock];
}
- (unsigned long long)maxIconCountForRoot { return 24; }
@end
#import "../PeachDock/SBCPUPeachDockRestore.h"
@interface SBCPUPeachUnarchiverFixture : NSObject
@property unsigned long long dockColumns;
@property unsigned long long filled;
@property BOOL capacityReadBeforeFill;
- (void)restore:(SBHIconModel *)model count:(unsigned long long)count;
@end
@implementation SBCPUPeachUnarchiverFixture
- (void)restore:(SBHIconModel *)model count:(unsigned long long)count {
    // Explicit fixture of the documented Dock-only delegate-before-list chain.
    self.dockColumns = [model maxIconCountForDockForIconStateUnarchiver:self];
    self.capacityReadBeforeFill = self.filled == 0 && self.dockColumns >= count;
    for (unsigned long long i = 0; i < count && i < self.dockColumns; ++i) ++self.filled;
}
@end
int main(void) { @autoreleasepool {
    assert(SBCPUPeachCapacityFixtureMain() == 0);
    SBHIconModel *model = [SBHIconModel new];
    SBCPUPeachUnarchiverFixture *before = [SBCPUPeachUnarchiverFixture new];
    [before restore:model count:9];
    assert(before.filled == 4 && !before.capacityReadBeforeFill);
    assert(SBCPUPeachDockRestoreReady());
    assert(!SBCPUPeachDockCapacityMethod(SBHIconModel.class,"maxIconCountForDock", "I@:"));
    assert(!SBCPUPeachDockCapacityMethod(SBHIconModel.class,"maxIconCountForDockForIconStateUnarchiver:", "Q@:Q"));
    unsigned previous = installs;
    SBCPUPeachDockInstallRestore();
    assert(installs == previous + 2);
    assert([model maxIconCountForDock] == 100);
    for (NSNumber *n in @[@4, @9, @100]) {
        SBCPUPeachUnarchiverFixture *fixture = [SBCPUPeachUnarchiverFixture new];
        [fixture restore:model count:n.unsignedLongLongValue];
        assert(fixture.capacityReadBeforeFill && fixture.filled == n.unsignedLongLongValue);
    }
    assert([model maxIconCountForRoot] == 24);
    assert([[SBIconListModel new] maxNumberOfIcons] == 4);
    puts("PASS: production restore hooks; delegate capacity BEFORE substitute list filling; ordinary model untouched; not on-device proof");
} return 0; }
