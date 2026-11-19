// Backdrop/filter recipe adapted from Lessica/TrollSpeed, MIT.
// See LICENSE.TrollSpeed and TEXT_ONLY_MODE.md for pinned provenance.
#import "SBCPUTextBackdropLabel.h"
#import "SBCPUTextOnlyTypography.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>

// Runtime lookup avoids a hard link to private classes/symbols.
@interface NSObject (SBCPUFilterFactory)
+ (id)filterWithName:(NSString *)name;
@end

// Explicit single-line baseline: center the CoreText ascent+descent box.
// CATextLayer's string is an opaque-white attributed string, never the UI color.
@interface SBCPUTextAlphaMask : CATextLayer
@property(nonatomic, strong) UILabel *glyphLabel;
@end
@implementation SBCPUTextAlphaMask
- (void)drawInContext:(CGContextRef)context {
    if (self.glyphLabel) {
        // Draw glyphs only, not a view snapshot. UIKit keeps baseline, alignment,
        // truncation and font substitution identical to the fallback label.
        UIGraphicsPushContext(context);
        [self.glyphLabel drawTextInRect:self.bounds];
        UIGraphicsPopContext();
        return;
    }
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
#ifdef SBCPU_TEXT_BACKDROP_TESTING
static SBCPUTextBackdropTestCounters gSBCPUBackdropTestCounters;
SBCPUTextBackdropTestCounters SBCPUTextBackdropReadTestCounters(void) { return gSBCPUBackdropTestCounters; }
void SBCPUTextBackdropResetTestCounters(void) { gSBCPUBackdropTestCounters = (SBCPUTextBackdropTestCounters){0, 0, 0, 0, 0}; }
#endif
@implementation SBCPUTextBackdropLabel {
    CALayer *_backdrop;
    SBCPUTextAlphaMask *_alphaMask;
    NSString *_lastText;
    NSAttributedString *_lastAttributedText;
    UIFont *_lastFont;
    CGRect _lastBounds;
    CGFloat _lastScale;
    NSTextAlignment _lastAlignment;
    NSInteger _lastNumberOfLines;
    NSLineBreakMode _lastLineBreakMode;
    BOOL _lastAdjustsFontSizeToFitWidth;
    CGFloat _lastMinimumScaleFactor;
    UIBaselineAdjustment _lastBaselineAdjustment;
    UISemanticContentAttribute _lastSemanticContentAttribute;
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    CGFloat _testScreenScaleOverride;
#endif
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
    _lastAttributedText = nil;
    _lastFont = nil;
    [CATransaction commit];
    [self setNeedsDisplay];
}

- (BOOL)createBackdrop {
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    // Exercise the real production mask/cache path without claiming simulator
    // support for the private CABackdropLayer filters or GPU compositing.
    _backdrop = [CALayer layer];
    _alphaMask = [SBCPUTextAlphaMask layer];
    _alphaMask.foregroundColor = UIColor.whiteColor.CGColor;
    _alphaMask.wrapped = NO;
    _alphaMask.alignmentMode = kCAAlignmentCenter;
    _alphaMask.truncationMode = kCATruncationNone;
    _backdrop.mask = _alphaMask;
    [self.layer addSublayer:_backdrop];
    gSBCPUBackdropTestCounters.backdropCreations++;
    return YES;
#else
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
#endif
}

- (void)syncBackdrop {
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    gSBCPUBackdropTestCounters.syncCalls++;
#endif
    if (!_realtimeInvertEnabled || self.text.length == 0) {
        if (_backdrop) [self clearBackdrop];
        return;
    }
#ifndef SBCPU_TEXT_BACKDROP_TESTING
    if (SBCPUBackdropUnavailable) return; // failed capability probes are process-cached
#endif
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    if (_testScreenScaleOverride > 0) scale = _testScreenScaleOverride;
#endif
    BOOL sameAttributedText = _lastAttributedText == self.attributedText ||
        (_lastAttributedText && self.attributedText && [_lastAttributedText isEqualToAttributedString:self.attributedText]);
    NSString *cacheText = _rowText ?: self.text;
    if (_backdrop && [_lastText isEqualToString:cacheText] && sameAttributedText && [_lastFont isEqual:self.font] &&
        CGRectEqualToRect(_lastBounds, self.bounds) && _lastScale == scale &&
        _lastAlignment == self.textAlignment && _lastNumberOfLines == self.numberOfLines &&
        _lastLineBreakMode == self.lineBreakMode && _lastAdjustsFontSizeToFitWidth == self.adjustsFontSizeToFitWidth &&
        _lastMinimumScaleFactor == self.minimumScaleFactor && _lastBaselineAdjustment == self.baselineAdjustment &&
        _lastSemanticContentAttribute == self.semanticContentAttribute) {
#ifdef SBCPU_TEXT_BACKDROP_TESTING
        gSBCPUBackdropTestCounters.cacheHits++;
#endif
        return;
    }
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
#ifdef SBCPU_TEXT_BACKDROP_TESTING
        gSBCPUBackdropTestCounters.maskRefreshes++;
#endif
        if ([self isKindOfClass:SBCPUCapsuleBackdropLabel.class] || self.attributedText.length) {
            UILabel *glyph = _alphaMask.glyphLabel;
            if (!glyph) {
                glyph = [[UILabel alloc] initWithFrame:self.bounds];
                glyph.backgroundColor = UIColor.clearColor;
                glyph.textColor = UIColor.whiteColor;
                _alphaMask.glyphLabel = glyph;
            }
            glyph.bounds = self.bounds;
            glyph.font = font;
            glyph.text = self.text;
            if (self.attributedText.length) {
                NSMutableAttributedString *maskText = [self.attributedText mutableCopy];
                [maskText addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor range:NSMakeRange(0, maskText.length)];
                [self.attributedText enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0, self.attributedText.length)
                    options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
                        (void)stop;
                        if (![value isKindOfClass:NSTextAttachment.class]) return;
                        NSTextAttachment *source = value;
                        NSTextAttachment *white = [NSTextAttachment new];
                        white.bounds = source.bounds;
                        white.image = [source.image imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
                        [maskText addAttribute:NSAttachmentAttributeName value:white range:range];
                    }];
                glyph.attributedText = maskText;
            }
            glyph.textAlignment = self.textAlignment;
            glyph.numberOfLines = self.numberOfLines;
            glyph.lineBreakMode = self.lineBreakMode;
            glyph.adjustsFontSizeToFitWidth = self.adjustsFontSizeToFitWidth;
            glyph.minimumScaleFactor = self.minimumScaleFactor;
            glyph.baselineAdjustment = self.baselineAdjustment;
            glyph.semanticContentAttribute = self.semanticContentAttribute;
        }
        [_alphaMask setNeedsDisplay];
        _lastText = [cacheText copy];
        _lastAttributedText = [self.attributedText copy];
        _lastFont = self.font;
        _lastBounds = self.bounds;
        _lastScale = scale;
        _lastAlignment = self.textAlignment;
        _lastNumberOfLines = self.numberOfLines;
        _lastLineBreakMode = self.lineBreakMode;
        _lastAdjustsFontSizeToFitWidth = self.adjustsFontSizeToFitWidth;
        _lastMinimumScaleFactor = self.minimumScaleFactor;
        _lastBaselineAdjustment = self.baselineAdjustment;
        _lastSemanticContentAttribute = self.semanticContentAttribute;
        [self setNeedsDisplay];
    } @catch (__unused NSException *exception) {
        SBCPUBackdropUnavailable = YES;
        [self clearBackdrop];
    } @finally {
        [CATransaction commit];
    }
}

- (void)invalidateBackdropTypography {
    _lastText = nil;
    _lastAttributedText = nil;
    [self setNeedsLayout];
}

- (void)setRealtimeInvertEnabled:(BOOL)enabled {
    if (_realtimeInvertEnabled == enabled) return;
    _realtimeInvertEnabled = enabled;
    [self syncBackdrop]; // includes initial text/font/bounds, before the next tick/layout
}
- (void)setText:(NSString *)text {
    if ((self.text == text) || [self.text isEqualToString:text]) return;
    [super setText:text];
    [self setNeedsLayout];
    if (text.length == 0 && _backdrop) [self clearBackdrop];
}
- (void)setAttributedText:(NSAttributedString *)text {
    if ((self.attributedText == text) || [self.attributedText isEqualToAttributedString:text]) return;
    [super setAttributedText:text];
    [self invalidateBackdropTypography];
}
- (void)setFont:(UIFont *)font {
    if ((self.font == font) || [self.font isEqual:font]) return;
    [super setFont:font];
    [self setNeedsLayout];
}
- (void)setTextColor:(UIColor *)color {
    if ((self.textColor == color) || [self.textColor isEqual:color]) return;
    [super setTextColor:color];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self syncBackdrop];
}
- (void)drawTextInRect:(CGRect)rect {
    if (!_backdrop) [super drawTextInRect:rect]; // fallback is never made transparent
}
#ifdef SBCPU_TEXT_BACKDROP_TESTING
- (void)sbcpu_testSyncBackdropAtScale:(CGFloat)scale {
    _testScreenScaleOverride = scale;
    [self syncBackdrop];
    _testScreenScaleOverride = 0;
}
- (UIImage *)sbcpu_testCopyAlphaMaskAtScale:(CGFloat)scale {
    if (!_alphaMask || CGRectIsEmpty(_alphaMask.bounds)) return nil;
    UIGraphicsBeginImageContextWithOptions(_alphaMask.bounds.size, NO, scale ?: 1);
    [_alphaMask drawInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
#endif
@end

#ifdef SBCPU_TEXT_BACKDROP_TESTING
UIImage *SBCPUTextBackdropCopyMaskImageForTesting(SBCPUTextBackdropLabel *label, CGFloat scale) {
    return [label sbcpu_testCopyAlphaMaskAtScale:scale];
}
#endif

@implementation SBCPUCapsuleBackdropLabel {
    NSString *_rowText;
    UIFont *_rowFont;
    UIColor *_rowColor;
    NSAttributedString *_rowAttributedText;
}
- (void)setHidden:(BOOL)hidden {
    if (self.hidden == hidden) return;
    [super setHidden:hidden];
    if (hidden) self.realtimeInvertEnabled = NO;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) self.realtimeInvertEnabled = NO;
}
- (void)sbcpu_setTextOnlyPlainText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    BOOL sameInputs = ((_rowText == text) || [_rowText isEqualToString:text]) &&
        ((_rowFont == font) || [_rowFont isEqual:font]) && ((_rowColor == color) || [_rowColor isEqual:color]);
    BOOL sameAttributedRow = self.attributedText == _rowAttributedText ||
        (_rowAttributedText && self.attributedText && [self.attributedText isEqualToAttributedString:_rowAttributedText]);
    // UILabel.text reflects the attachment replacement character. Do not
    // overwrite valid attributed text just to restore the raw metric prefix.
    if (sameInputs && sameAttributedRow && [self.font isEqual:font] && [self.textColor isEqual:color]) return;
    if (![self.text isEqualToString:text]) self.text = text;
    if (![self.font isEqual:font]) self.font = font;
    if (![self.textColor isEqual:color]) self.textColor = color;
    NSAttributedString *row = SBCPUTextOnlyAttributedRow(text, font, color);
    self.attributedText = row;
    _rowText = [text copy]; _rowFont = font; _rowColor = color; _rowAttributedText = row;
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    gSBCPUBackdropTestCounters.styledAttributeBuilds++;
#endif
}
- (void)sbcpu_applyTextOnlyColor:(UIColor *)color {
    [self sbcpu_setTextOnlyPlainText:_rowText ?: self.text font:self.font color:color];
}
- (void)setTextAlignment:(NSTextAlignment)value {
    if (self.textAlignment == value) return;
    [super setTextAlignment:value]; [self invalidateBackdropTypography];
}
- (void)setNumberOfLines:(NSInteger)value {
    if (self.numberOfLines == value) return;
    [super setNumberOfLines:value]; [self invalidateBackdropTypography];
}
- (void)setLineBreakMode:(NSLineBreakMode)value {
    if (self.lineBreakMode == value) return;
    [super setLineBreakMode:value]; [self invalidateBackdropTypography];
}
- (void)setAdjustsFontSizeToFitWidth:(BOOL)value {
    if (self.adjustsFontSizeToFitWidth == value) return;
    [super setAdjustsFontSizeToFitWidth:value]; [self invalidateBackdropTypography];
}
- (void)setMinimumScaleFactor:(CGFloat)value {
    if (self.minimumScaleFactor == value) return;
    [super setMinimumScaleFactor:value]; [self invalidateBackdropTypography];
}
- (void)setBaselineAdjustment:(UIBaselineAdjustment)value {
    if (self.baselineAdjustment == value) return;
    [super setBaselineAdjustment:value]; [self invalidateBackdropTypography];
}
- (void)setSemanticContentAttribute:(UISemanticContentAttribute)value {
    if (self.semanticContentAttribute == value) return;
    [super setSemanticContentAttribute:value]; [self invalidateBackdropTypography];
}
@end
