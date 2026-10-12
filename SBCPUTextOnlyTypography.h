#ifndef SBCPU_TEXT_ONLY_TYPOGRAPHY_H
#define SBCPU_TEXT_ONLY_TYPOGRAPHY_H
#import <UIKit/UIKit.h>

// Monochrome vector fallback keeps indicators visible when SF Symbols are absent.
static inline UIImage *SBCPUTextOnlyFallbackIcon(BOOL thermometer, UIColor *color, CGFloat side) {
    CGFloat scale = UIScreen.mainScreen.scale ?: 2.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, scale);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(c, (color ?: UIColor.labelColor).CGColor);
    CGContextSetFillColorWithColor(c, (color ?: UIColor.labelColor).CGColor);
    CGContextSetLineWidth(c, MAX(1.0, side * 0.11));
    CGContextSetLineCap(c, kCGLineCapRound); CGContextSetLineJoin(c, kCGLineJoinRound);
    if (thermometer) {
        CGFloat x=side*.5, bulb=side*.22;
        CGContextStrokeEllipseInRect(c, CGRectMake(x-bulb, side*.60, bulb*2, bulb*2));
        CGContextMoveToPoint(c,x,side*.68); CGContextAddLineToPoint(c,x,side*.18); CGContextStrokePath(c);
        CGContextMoveToPoint(c,side*.30,side*.18); CGContextAddLineToPoint(c,side*.70,side*.18); CGContextStrokePath(c);
    } else {
        CGContextMoveToPoint(c,side*.58,side*.08); CGContextAddLineToPoint(c,side*.25,side*.53);
        CGContextAddLineToPoint(c,side*.48,side*.53); CGContextAddLineToPoint(c,side*.40,side*.92);
        CGContextAddLineToPoint(c,side*.77,side*.40); CGContextAddLineToPoint(c,side*.55,side*.40);
        CGContextClosePath(c); CGContextFillPath(c);
    }
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// SF Symbols are preferred, but the vector fallback is deterministic on real devices.
static inline NSAttributedString *SBCPUTextOnlyAttributedRow(NSString *plain, UIFont *font, UIColor *color) {
    if (!plain.length) return [[NSAttributedString alloc] initWithString:@""];
    UIColor *ink=color ?: UIColor.labelColor;
    NSMutableAttributedString *result=[[NSMutableAttributedString alloc] initWithString:plain attributes:@{
        NSFontAttributeName:font, NSForegroundColorAttributeName:ink}];
    NSArray *pairs=@[@[@"TEMP ",@"thermometer"], @[@"I ",@"bolt.fill"]];
    for (NSArray *pair in pairs) {
        NSRange range=[result.string rangeOfString:pair[0]]; if (range.location==NSNotFound) continue;
        UIImage *symbol=[UIImage systemImageNamed:pair[1]];
        CGFloat side=MAX(1,font.pointSize*.82);
        if (symbol) symbol=[symbol imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal];
        else symbol=SBCPUTextOnlyFallbackIcon([pair[0] hasPrefix:@"TEMP"],ink,side);
        NSTextAttachment *attachment=[NSTextAttachment new]; attachment.image=symbol;
        attachment.bounds=CGRectMake(0,(font.capHeight-side)*.5,side,side);
        [result replaceCharactersInRange:range withAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    }
    return result;
}
#endif
