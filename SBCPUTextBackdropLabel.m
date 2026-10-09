// Backdrop/filter recipe adapted from Lessica/TrollSpeed, MIT.
// See LICENSE.TrollSpeed and TEXT_ONLY_MODE.md for pinned provenance.
#import "SBCPUTextBackdropLabel.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>

// Runtime lookup avoids a hard link to private classes/symbols.
@interface NSObject (SBCPUFilterFactory)
+ (id)filterWithName:(NSString *)name;
@end

// Explicit single-line baseline: center the CoreText ascent+descent box.
// CATextLayer's string is an opaque-white attributed string, never the UI color.
@interface SBCPUTextAlphaMask : CATextLayer
@end
@implementation SBCPUTextAlphaMask
- (void)drawInContext:(CGContextRef)context {
    NSAttributedString *string = self.string;
    if (!string.length) return;
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);
    CGFloat ascent = 0, descent = 0;
    double width = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, 0, self.bounds.size.height);
    CGContextScaleCTM(context, 1, -1);
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, (self.bounds.size.width - width) / 2,
        (self.bounds.size.height - ascent - descent) / 2 + descent);
    CTLineDraw(line, context);
    CGContextRestoreGState(context);
    CFRelease(line);
}
@end

// Main-thread UIKit code. Cache a failed capability/KVC probe for this process.
static BOOL SBCPUBackdropUnavailable = NO;
@implementation SBCPUTextBackdropLabel {
    CALayer *_backdrop;
    SBCPUTextAlphaMask *_alphaMask;
    NSString *_lastText;
    UIFont *_lastFont;
    CGRect _lastBounds;
    CGFloat _lastScale;
    BOOL _realtimeInvertEnabled;
}
@synthesize realtimeInvertEnabled = _realtimeInvertEnabled;

- (void)clearBackdrop {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_backdrop removeFromSuperlayer];
    _backdrop.mask = nil;
    _backdrop.filters = nil;
    _backdrop = nil;
    _alphaMask = nil;
    _lastText = nil;
    _lastFont = nil;
    [CATransaction commit];
    [self setNeedsDisplay];
}

- (BOOL)createBackdrop {
    if (SBCPUBackdropUnavailable) return NO;
    @try {
        Class backdropClass = NSClassFromString(@"CABackdropLayer");
        Class filterClass = NSClassFromString(@"CAFilter");
        if (!backdropClass || ![backdropClass isSubclassOfClass:CALayer.class] ||
            ![filterClass respondsToSelector:@selector(filterWithName:)]) {
            SBCPUBackdropUnavailable = YES;
            return NO;
        }
        NSMutableArray *filters = [NSMutableArray array];
        NSArray *names = @[@"gaussianBlur", @"colorBrightness", @"colorContrast", @"colorSaturate", @"colorInvert"];
        NSArray *amounts = @[@50.0, @(-0.285), @1000.0, @0.0];
        for (NSUInteger i = 0; i < names.count; i++) {
            id filter = [filterClass filterWithName:names[i]];
            if (!filter) { SBCPUBackdropUnavailable = YES; return NO; }
            if (i < amounts.count) [filter setValue:amounts[i] forKey:i == 0 ? @"inputRadius" : @"inputAmount"];
            if (i == 0) [filter setValue:@YES forKey:@"inputNormalizeEdges"];
            [filters addObject:filter];
        }
        _backdrop = [backdropClass layer];
        if (!_backdrop) { SBCPUBackdropUnavailable = YES; return NO; }
        _backdrop.filters = filters;
        _alphaMask = [SBCPUTextAlphaMask layer];
        _alphaMask.foregroundColor = UIColor.whiteColor.CGColor;
        _alphaMask.wrapped = NO;
        _alphaMask.alignmentMode = kCAAlignmentCenter;
        _alphaMask.truncationMode = kCATruncationNone;
        _backdrop.mask = _alphaMask;
        [self.layer addSublayer:_backdrop];
        return YES;
    } @catch (__unused NSException *exception) {
        SBCPUBackdropUnavailable = YES;
        [self clearBackdrop];
        return NO;
    }
}

- (void)syncBackdrop {
    if (!_realtimeInvertEnabled || self.text.length == 0) {
        if (_backdrop) [self clearBackdrop];
        return;
    }
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    if (_backdrop && [_lastText isEqualToString:self.text] && [_lastFont isEqual:self.font] &&
        CGRectEqualToRect(_lastBounds, self.bounds) && _lastScale == scale) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        if (!_backdrop && ![self createBackdrop]) return;
        UIFont *font = self.font ?: [UIFont systemFontOfSize:13];
        CGFloat width = [self.text sizeWithAttributes:@{NSFontAttributeName:font}].width;
        // Fit every selected field, without wrapping or ellipsis, just like the row policy.
        CGFloat ratio = width > 0 ? MIN(1, MAX(0.001, self.bounds.size.width / width)) : 1;
        UIFont *fittedFont = [font fontWithSize:font.pointSize * ratio];
        _backdrop.frame = self.bounds;
        _alphaMask.frame = _backdrop.bounds;
        _alphaMask.contentsScale = scale;
        _alphaMask.string = [[NSAttributedString alloc] initWithString:self.text attributes:@{
            NSFontAttributeName:fittedFont, NSForegroundColorAttributeName:UIColor.whiteColor}];
        [_alphaMask setNeedsDisplay];
        _lastText = [self.text copy];
        _lastFont = self.font;
        _lastBounds = self.bounds;
        _lastScale = scale;
        [self setNeedsDisplay];
    } @catch (__unused NSException *exception) {
        SBCPUBackdropUnavailable = YES;
        [self clearBackdrop];
    } @finally {
        [CATransaction commit];
    }
}

- (void)setRealtimeInvertEnabled:(BOOL)enabled {
    _realtimeInvertEnabled = enabled;
    [self syncBackdrop]; // includes initial text/font/bounds, before the next tick/layout
}
- (void)setText:(NSString *)text {
    if ((self.text == text) || [self.text isEqualToString:text]) return;
    [super setText:text];
    [self setNeedsLayout];
    if (text.length == 0 && _backdrop) [self clearBackdrop];
}
- (void)setFont:(UIFont *)font {
    if ([self.font isEqual:font]) return;
    [super setFont:font];
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self syncBackdrop];
}
- (void)drawTextInRect:(CGRect)rect {
    if (!_backdrop) [super drawTextInRect:rect]; // fallback is never made transparent
}
@end
