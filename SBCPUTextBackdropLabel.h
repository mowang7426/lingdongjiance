#import <UIKit/UIKit.h>

// Pure-text and explicitly opted-in capsule glyphs only. textColor is the fallback.
@interface SBCPUTextBackdropLabel : UILabel
@property(nonatomic) BOOL realtimeInvertEnabled;
@end

// Preserve UIKit typography (including replacement fonts) in ordinary capsules.
@interface SBCPUCapsuleBackdropLabel : SBCPUTextBackdropLabel
@end
