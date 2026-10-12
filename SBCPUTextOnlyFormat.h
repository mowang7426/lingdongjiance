#ifndef SBCPU_TEXT_ONLY_FORMAT_H
#define SBCPU_TEXT_ONLY_FORMAT_H
#import <UIKit/UIKit.h>
#include <math.h>

// Presentation inputs only: no thermal/charging status or controller settings.
typedef struct {
    BOOL cpu, frequency, fps, battery, temperature, current, sim1, sim2;
} SBCPUTextOnlyFields;

static inline NSString *SBCPUTextOnlyCompactValue(NSString *value, NSString *unit, BOOL allowNegative) {
    if (![value isKindOfClass:[NSString class]]) return [@"--" stringByAppendingString:unit];
    NSString *compact = [[value componentsSeparatedByCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
    if (![compact hasSuffix:unit]) return [@"--" stringByAppendingString:unit];
    NSString *number = [compact substringToIndex:compact.length - unit.length];
    NSScanner *scanner = [NSScanner scannerWithString:number];
    scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double parsed = 0;
    if (![scanner scanDouble:&parsed] || !scanner.isAtEnd || !isfinite(parsed) ||
        (!allowNegative && parsed < 0)) return [@"--" stringByAppendingString:unit];
    return [number stringByAppendingString:unit];
}

static inline NSString *SBCPUTextOnlySignal(NSArray<NSDictionary *> *signals, NSInteger slot) {
    NSString *dbm = @"--";
    for (NSDictionary *signal in signals) {
        if ([signal[@"slot"] integerValue] == slot) {
            NSString *raw = [signal[@"dbm"] isKindOfClass:[NSString class]] ? signal[@"dbm"] : nil;
            NSString *validated = SBCPUTextOnlyCompactValue([raw stringByAppendingString:@"dBm"], @"dBm", YES);
            dbm = [validated substringToIndex:validated.length - 3];
            break;
        }
    }
    // Deliberately omit carrier names/band/technology; these remain in ordinary UI.
    return [NSString stringWithFormat:@"%@dBm", dbm];
}

static inline NSString *SBCPUTextOnlyRow(SBCPUTextOnlyFields fields,
    NSString *cpu, NSString *frequency, NSString *fps, NSString *battery,
    NSString *temperature, NSString *current, NSArray<NSDictionary *> *signals) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (fields.cpu) [parts addObject:[@"CPU " stringByAppendingString:SBCPUTextOnlyCompactValue(cpu, @"%", NO)]];
    if (fields.frequency) [parts addObject:SBCPUTextOnlyCompactValue(frequency, @"MHz", NO)];
    if (fields.fps) [parts addObject:[@"FPS " stringByAppendingString:SBCPUTextOnlyCompactValue(fps, @"", NO)]];
    if (fields.battery) [parts addObject:[@"BAT " stringByAppendingString:SBCPUTextOnlyCompactValue(battery, @"%", NO)]];
    if (fields.temperature) [parts addObject:[@"TEMP " stringByAppendingString:SBCPUTextOnlyCompactValue(temperature, @"°C", YES)]];
    if (fields.current) [parts addObject:[@"I " stringByAppendingString:SBCPUTextOnlyCompactValue(current, @"mA", YES)]];
    if (fields.sim1) [parts addObject:[@"S1 " stringByAppendingString:SBCPUTextOnlySignal(signals, 1)]];
    if (fields.sim2) [parts addObject:[@"S2 " stringByAppendingString:SBCPUTextOnlySignal(signals, 2)]];
    return [parts componentsJoinedByString:@" "];
}
#endif

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
