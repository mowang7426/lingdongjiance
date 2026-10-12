#ifndef SBCPU_TEXT_TYPOGRAPHY_H
#define SBCPU_TEXT_TYPOGRAPHY_H
#import <UIKit/UIKit.h>
// Builds the rendered row without emoji: SF Symbols are monochrome template images;
// the textual label remains the fallback when a symbol is unavailable.
static inline NSAttributedString *SBCPUTextOnlyAttributedRow(NSString *plain, UIFont *font, UIColor *color) {
    if (!plain.length) return [[NSAttributedString alloc] initWithString:@""];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:plain attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: color ?: UIColor.labelColor}];
    NSArray *pairs = @[@[@"TEMP ", @"thermometer"], @[@"I ", @"bolt.fill"]];
    for (NSArray *pair in pairs) {
        NSRange range = [result.string rangeOfString:pair[0]];
        if (range.location == NSNotFound) continue;
        UIImage *symbol = [UIImage systemImageNamed:pair[1]];
        if (!symbol) continue; // keep the text label as a safe system fallback
        symbol = [symbol imageWithTintColor:color ?: UIColor.labelColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        NSTextAttachment *attachment = [NSTextAttachment new];
        attachment.image = symbol;
        CGFloat side = MAX(1, font.pointSize * 0.82);
        attachment.bounds = CGRectMake(0, (font.capHeight - side) * 0.5, side, side);
        [result replaceCharactersInRange:range
                     withAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    }
    return result;
}

#endif
