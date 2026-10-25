#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Guarded runtime probe shared by the rendering and layout paths.
BOOL SBCPUPeachDockIconEditingActive(void);

// Owns only its wrapper/overlay. SpringBoard's actual icon views stay intact.
@interface SBCPUPeachDockEdgeTransition : NSObject
+ (BOOL)sbcpu_peach_dock_listView:(nullable UIView *)listView
       ownsScrollView:(nullable UIScrollView *)scrollView
          contentView:(nullable UIView *)contentView
             clipView:(nullable UIView *)clipView;
+ (instancetype)transitionForListView:(UIView *)listView
                          scrollView:(UIScrollView *)scrollView
                         contentView:(UIView *)contentView
                            clipView:(UIView *)clipView;
- (void)layout;
- (void)beginInteraction;
- (void)setIconEditing:(BOOL)editing;
- (void)scrollDidChange;
- (void)endInteraction;
- (void)beginSpring;
- (void)endSpring;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
