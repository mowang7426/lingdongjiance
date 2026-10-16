#ifndef SBCPU_TEXT_FPS_BUDGET_H
#define SBCPU_TEXT_FPS_BUDGET_H
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import "SBCPUTextSlotPolicy.h"

/* Same UIFont and attributes as the FPS UILabel, including its digit features.
   CTLine accounts for advances AND rightmost ink, unlike a character count.
   No current sample enters this API. 2pt clearance covers pixel rounding at
   1x/2x/3x; it belongs to FPS, not the separate separator or another metric. */
static inline CGFloat SBCPUTextFPSGlyphExtent(NSString *text, UIFont *font) {
    NSAttributedString *string=[[NSAttributedString alloc] initWithString:text
        attributes:@{NSFontAttributeName:font}];
    CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);
    CGFloat advance=(CGFloat)CTLineGetTypographicBounds(line,NULL,NULL,NULL);
    CGRect ink=CTLineGetBoundsWithOptions(line,kCTLineBoundsUseGlyphPathBounds);
    CFRelease(line);
    return MAX(advance,CGRectIsNull(ink)?0:CGRectGetMaxX(ink));
}
static inline CGFloat SBCPUTextFPSConfiguredWidth(UIFont *font) {
    /* Main-thread HUD configuration cache: separate font descriptors/weights
       cannot share a budget. Repeated sampling/layout only looks up this key. */
    static NSCache<UIFont *,NSNumber *> *cache;
    if (!cache) cache=[NSCache new];
    NSNumber *cached=[cache objectForKey:font];
    if (cached) return cached.doubleValue;
    CGFloat extent=SBCPUTextFPSGlyphExtent(@"FPS--",font);
    /* Exhaust all three-digit templates; shorter forms are included explicitly.
       This also handles replacement fonts with non-uniform digit advances. */
    for (int n=0;n<1000;n++) {
        NSString *template=[NSString stringWithFormat:@"FPS%d",n];
        extent=MAX(extent,SBCPUTextFPSGlyphExtent(template,font));
    }
    for (NSString *template in @[@"FPS0",@"FPS60",@"FPS99"])
        extent=MAX(extent,SBCPUTextFPSGlyphExtent(template,font));
    CGFloat width=MAX(SBCPUTextSlotWidth(2,font.pointSize,CGFLOAT_MAX),ceil(extent)+2);
    [cache setObject:@(width) forKey:font];
    return width;
}
#endif
