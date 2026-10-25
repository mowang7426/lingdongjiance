#import <UIKit/UIKit.h>

// iOS16.2 SBIconCoordinate is { column, row }, both 1-based. Verified from
// coordinateAtPoint:metrics: and SBIconCoordinateForGridCellIndex machine code;
// the runtime encoding qq alone does NOT encode member names/order semantics.
typedef struct {
    long long col;
    long long row;
} SBCPUPeachDockIconCoordinate;

@interface SBIconView : UIView
@property (nonatomic, readonly) id icon;
@end

@interface SBIconListModel : NSObject
- (instancetype)initWithFolder:(id)folder maxIconCount:(unsigned long long)maxIconCount;
@end

@interface SBIconListGridLayoutConfiguration : NSObject
@property (nonatomic) unsigned long long numberOfPortraitRows;
@property (nonatomic) unsigned long long numberOfPortraitColumns;
@property (nonatomic) unsigned long long numberOfLandscapeRows;
@property (nonatomic) unsigned long long numberOfLandscapeColumns;
@end

@interface SBIconListGridLayout : NSObject
@property (nonatomic, readonly, copy) SBIconListGridLayoutConfiguration *layoutConfiguration;
@end

@interface SBHDefaultIconListLayoutProvider : NSObject
- (id)layoutForIconLocation:(id)iconLocation;
@end

@interface SBIconListView : UIView
@property (nonatomic, readonly, copy) NSArray *visibleIcons;
@property (nonatomic, copy) NSString *iconLocation;
@end

// Declarations only: never implements/overrides a system method in a category.
@interface SBIconListView (SBCPUPeachDockDropMappingDeclarations)
// Signatures enumerated from this device's iOS16.2 SpringBoardHome metadata.
- (CGPoint)centerForIconCoordinate:(SBCPUPeachDockIconCoordinate)coordinate metrics:(id)metrics;
- (CGPoint)originForIconAtCoordinate:(SBCPUPeachDockIconCoordinate)coordinate metrics:(id)metrics options:(NSUInteger)options;
- (NSUInteger)columnAtPoint:(CGPoint)point metrics:(id)metrics fractionOfDistanceThroughColumn:(double *)fraction;
- (void)layoutIconsNow;
- (void)layoutIconsIfNeededUsingAnimator:(id)animator options:(NSUInteger)options;
- (void)layoutAndCreateIcon:(id)icon;
- (void)layoutAndCreateIcon:(id)icon atIndex:(NSUInteger)index;
@end

@interface SBDockIconListView : SBIconListView
- (CGPoint)originForIconAtCoordinate:(SBCPUPeachDockIconCoordinate)coordinate
                       numberOfIcons:(unsigned long long)numberOfIcons;
@end

@interface SBDockView : UIView
@property (nonatomic, retain) UIView *backgroundView;
@property (nonatomic, readonly) SBDockIconListView *dockListView;
@end

@interface SBDockIconListView (SBCPUPeachDockDeclarations)
+ (unsigned long long)maxIcons;
@end
