#import <UIKit/UIKit.h>

// Pure-text and explicitly opted-in capsule glyphs only. textColor is the fallback.
@interface SBCPUTextBackdropLabel : UILabel
@property(nonatomic) BOOL realtimeInvertEnabled;
#ifdef SBCPU_TEXT_BACKDROP_TESTING
- (void)sbcpu_testSyncBackdropAtScale:(CGFloat)scale;
- (UIImage *)sbcpu_testCopyAlphaMaskAtScale:(CGFloat)scale;
#endif
@end

// Preserve UIKit typography (including replacement fonts) in ordinary capsules.
@interface SBCPUCapsuleBackdropLabel : SBCPUTextBackdropLabel
// Text-only HUD rows rebuild attachment-backed typography only when their inputs change.
- (void)sbcpu_setTextOnlyPlainText:(NSString *)text font:(UIFont *)font color:(UIColor *)color;
- (void)sbcpu_applyTextOnlyColor:(UIColor *)color;
@end

// One renderer per pure-text HUD. The two HUDs can share the same UIWindow.
@interface SBCPUTextSlotHost : SBCPUTextBackdropLabel
- (void)sbcpu_setLiveInversionRequested:(BOOL)requested;
#ifdef SBCPU_TEXT_BACKDROP_TESTING
- (void)sbcpu_testSyncSharedAtScale:(CGFloat)scale;
- (CALayer *)sbcpu_testSharedBackdrop;
- (void)sbcpu_testRejectSharedBackdrop;
#endif
@end

#ifdef SBCPU_TEXT_BACKDROP_TESTING
// Test-only counters and mask export; absent from production builds.
typedef struct {
    NSUInteger syncCalls;
    NSUInteger cacheHits;
    NSUInteger maskRefreshes;
    NSUInteger backdropCreations;
    NSUInteger styledAttributeBuilds;
    NSUInteger sharedCreations;
    NSUInteger sharedMaskWrites;
} SBCPUTextBackdropTestCounters;
SBCPUTextBackdropTestCounters SBCPUTextBackdropReadTestCounters(void);
void SBCPUTextBackdropResetTestCounters(void);
UIImage *SBCPUTextBackdropCopyMaskImageForTesting(SBCPUTextBackdropLabel *label, CGFloat scale);
#endif
