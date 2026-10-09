#import <UIKit/UIKit.h>

// Only the pure-text overlay uses this class. textColor remains the fallback.
@interface SBCPUTextBackdropLabel : UILabel
@property(nonatomic) BOOL realtimeInvertEnabled;
@end
