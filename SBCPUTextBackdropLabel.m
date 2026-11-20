// Backdrop/filter recipe adapted from Lessica/TrollSpeed, MIT.
// See LICENSE.TrollSpeed and TEXT_ONLY_MODE.md for pinned provenance.
#import "SBCPUTextBackdropLabel.h"
#import "SBCPUTextOnlyTypography.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#import <math.h>
#import <stdlib.h>

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
static BOOL gSBCPUFailNextSharedCreation;
void SBCPUTextBackdropFailNextSharedCreation(void) { gSBCPUFailNextSharedCreation = YES; }
SBCPUTextBackdropTestCounters SBCPUTextBackdropReadTestCounters(void) { return gSBCPUBackdropTestCounters; }
void SBCPUTextBackdropResetTestCounters(void) { gSBCPUBackdropTestCounters = (SBCPUTextBackdropTestCounters){0, 0, 0, 0, 0, 0, 0}; }
#endif
// mem5 radius is retained only for the compatibility renderer.
static const CGFloat SBCPUSharedBlurRadius = 8.0;
static CALayer *SBCPUCreateLiveTextBackdrop(CGFloat radius, BOOL shared) {
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    // Structural surrogate only; never exercises the private compositor.
    if (shared && gSBCPUFailNextSharedCreation) { gSBCPUFailNextSharedCreation = NO; return nil; }
    (void)radius; (void)shared;
    return [CALayer layer];
#else
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    Class filterClass = NSClassFromString(@"CAFilter");
    if (!backdropClass || ![backdropClass isSubclassOfClass:CALayer.class] ||
        ![filterClass respondsToSelector:@selector(filterWithName:)]) return nil;
    NSMutableArray *filters = [NSMutableArray array];
    NSArray *names = @[@"gaussianBlur", @"colorBrightness", @"colorContrast", @"colorSaturate", @"colorInvert"];
    NSArray *amounts = @[@(radius), @(-0.285), @1000.0, @0.0];
    for (NSUInteger i = 0; i < names.count; i++) {
        id filter = [filterClass filterWithName:names[i]];
        if (!filter) return nil;
        if (i < amounts.count) [filter setValue:amounts[i] forKey:i == 0 ? @"inputRadius" : @"inputAmount"];
        if (i == 0) [filter setValue:@YES forKey:@"inputNormalizeEdges"];
        [filters addObject:filter];
    }
    CALayer *backdrop = [backdropClass layer];
    backdrop.filters = filters;
    if (!backdrop || (shared && ![backdrop.filters isEqualToArray:filters])) return nil;
    return backdrop;
#endif
}

@interface SBCPUTextBackdropLabel (SBCPUSharedMaskComponent)
- (BOOL)sbcpu_alphaMaskMatchesScale:(CGFloat)scale;
- (BOOL)sbcpu_refreshAlphaMaskAtScale:(CGFloat)scale;
- (CALayer *)sbcpu_prepareSharedMaskAtScale:(CGFloat)scale ink:(CGRect *)ink changed:(BOOL *)changed;
- (void)sbcpu_useSharedGlyph;
- (void)sbcpu_leaveSharedMask;
@end

@implementation SBCPUTextBackdropLabel {
    CALayer *_backdrop;
    BOOL _sbcpuSharedMask;
    SBCPUTextAlphaMask *_alphaMask;
    CALayer *_sbcpuSharedGlyph;
    CGRect _sbcpuInk;
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
    if (SBCPUBackdropUnavailable) return NO;
    _backdrop = SBCPUCreateLiveTextBackdrop(50.0, NO);
    if (!_backdrop) { SBCPUBackdropUnavailable = YES; return NO; }
    [self.layer addSublayer:_backdrop];
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    gSBCPUBackdropTestCounters.backdropCreations++;
#endif
    return YES;
}

- (void)syncBackdrop {
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    gSBCPUBackdropTestCounters.syncCalls++;
#endif
    if (_sbcpuSharedMask) return; // host batches all slot changes together
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
    if (_backdrop && [self sbcpu_alphaMaskMatchesScale:scale]) {
#ifdef SBCPU_TEXT_BACKDROP_TESTING
        gSBCPUBackdropTestCounters.cacheHits++;
#endif
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        if (!_backdrop && ![self createBackdrop]) return;
        if ([self sbcpu_refreshAlphaMaskAtScale:scale] || !_backdrop.mask) {
            _backdrop.frame = self.bounds;
            _alphaMask.frame = _backdrop.bounds;
            _backdrop.mask = _alphaMask;
            [self setNeedsDisplay];
        }
    } @catch (__unused NSException *exception) {
        SBCPUBackdropUnavailable = YES;
        [self clearBackdrop];
    } @finally {
        [CATransaction commit];
    }
}

- (BOOL)sbcpu_alphaMaskMatchesScale:(CGFloat)scale {
    BOOL sameAttributedText = _lastAttributedText == self.attributedText ||
    (_lastAttributedText && self.attributedText && [_lastAttributedText isEqualToAttributedString:self.attributedText]);
    // Cache the rendered UILabel string (including attachment placeholders).
    // Raw row inputs are owned and compared only by the capsule subclass.
    NSString *cacheText = self.text;
    return _alphaMask && [_lastText isEqualToString:cacheText] && sameAttributedText && [_lastFont isEqual:self.font] &&
    CGRectEqualToRect(_lastBounds, self.bounds) && _lastScale == scale &&
    _lastAlignment == self.textAlignment && _lastNumberOfLines == self.numberOfLines &&
    _lastLineBreakMode == self.lineBreakMode && _lastAdjustsFontSizeToFitWidth == self.adjustsFontSizeToFitWidth &&
    _lastMinimumScaleFactor == self.minimumScaleFactor && _lastBaselineAdjustment == self.baselineAdjustment &&
    _lastSemanticContentAttribute == self.semanticContentAttribute;
}

- (BOOL)sbcpu_refreshAlphaMaskAtScale:(CGFloat)scale {
    if ([self sbcpu_alphaMaskMatchesScale:scale]) {
#ifdef SBCPU_TEXT_BACKDROP_TESTING
        gSBCPUBackdropTestCounters.cacheHits++;
#endif
        return NO;
    }
    UIFont *font = self.font ?: [UIFont systemFontOfSize:13];
    CGFloat width = [self.text sizeWithAttributes:@{NSFontAttributeName:font}].width;
    // Fit every selected field, without wrapping or ellipsis, just like the row policy.
    CGFloat ratio = width > 0 ? MIN(1, MAX(0.001, self.bounds.size.width / width)) : 1;
    UIFont *fittedFont = [font fontWithSize:font.pointSize * ratio];
    if (!_alphaMask) {
        _alphaMask = [SBCPUTextAlphaMask layer];
        _alphaMask.foregroundColor = UIColor.whiteColor.CGColor;
        _alphaMask.wrapped = NO;
        _alphaMask.alignmentMode = kCAAlignmentCenter;
        _alphaMask.truncationMode = kCATruncationNone;
        _alphaMask.masksToBounds = YES;
    }
    _alphaMask.bounds = (CGRect){CGPointZero,self.bounds.size};
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
    _lastText = [self.text copy];
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
    return YES;
}

// Rasterize the same glyph renderer as mem5, not the screen or a UIView snapshot.
// Transparent slot margins do not need to be included in the expensive backdrop.
- (CALayer *)sbcpu_prepareSharedMaskAtScale:(CGFloat)scale ink:(CGRect *)ink changed:(BOOL *)changed {
    BOOL refresh = [self sbcpu_refreshAlphaMaskAtScale:scale];
    if (refresh || !_sbcpuSharedGlyph) {
        CGSize size = _alphaMask.bounds.size;
        CGFloat w = ceil(size.width * scale), h = ceil(size.height * scale);
        if (!isfinite(w) || !isfinite(h) || w < 1 || h < 1 || w > 8192 || h > 2048 || w*h > 4194304) return nil;
        size_t width = (size_t)w, height = (size_t)h, stride = width * 4;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, stride, space,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(space);
        if (!ctx) return nil;
        CGRect inkFrame = CGRectNull;
        CGImageRef image = NULL;
        @try {
            UIGraphicsBeginImageContextWithOptions(size, NO, scale);
            @try {
                [_alphaMask drawInContext:UIGraphicsGetCurrentContext()];
                CGImageRef glyphImage = UIGraphicsGetImageFromCurrentImageContext().CGImage;
                if (glyphImage) image = CGImageRetain(glyphImage);
            } @finally { UIGraphicsEndImageContext(); }
            if (!image) return nil;
            // Only alpha bounds are scanned; native mem5 mask layers remain
            // the compositor input. No screen capture or timed polling.
            CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), image);
            const uint8_t *rgba = (const uint8_t *)CGBitmapContextGetData(ctx);
            size_t left = width, top = height, right = 0, bottom = 0;
            for (size_t y = 0; y < height; y++) for (size_t x = 0; x < width; x++) {
                if (!rgba[y * stride + x * 4 + 3]) continue;
                left = MIN(left, x); top = MIN(top, y);
                right = MAX(right, x+1); bottom = MAX(bottom, y+1);
            }
            if (right > left && bottom > top) {
                inkFrame = CGRectMake(left/scale, top/scale, (right-left)/scale, (bottom-top)/scale);
                // Keep the exact UIKit bitmap, not the alpha-scan context.
            }
            // Reparent the ORIGINAL mem5 alpha layer, not a rescaled bitmap.
            // The temporary image above measures ink only and is released here.
            _sbcpuSharedGlyph = _alphaMask;
            _sbcpuInk = inkFrame;
            *changed = YES;
        } @finally {
            if (image) CGImageRelease(image);
            CGContextRelease(ctx);
        }
    }
    *ink = _sbcpuInk;
    return _sbcpuSharedGlyph;
}

- (void)sbcpu_useSharedGlyph {
    if (_sbcpuSharedMask) return;
    if (_backdrop) {
        [_backdrop removeFromSuperlayer];
        _backdrop.mask = nil;
        _backdrop.filters = nil;
        _backdrop = nil;
    }
    _realtimeInvertEnabled = NO;
    _sbcpuSharedMask = YES;
    [self setNeedsDisplay];
}

- (void)sbcpu_leaveSharedMask {
    [_sbcpuSharedGlyph removeFromSuperlayer];
    _sbcpuSharedGlyph = nil;
    if (!_sbcpuSharedMask) return;
    _sbcpuSharedMask = NO;
    [self setNeedsDisplay];
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
    if (_sbcpuSharedMask && [self.superview isKindOfClass:SBCPUTextSlotHost.class])
        [self.superview setNeedsLayout];
}
- (void)setHidden:(BOOL)hidden {
    if (self.hidden == hidden) return;
    [super setHidden:hidden];
    if ([self.superview isKindOfClass:SBCPUTextSlotHost.class]) [self.superview setNeedsLayout];
}
- (void)drawTextInRect:(CGRect)rect {
    if (!_backdrop && !_sbcpuSharedMask) [super drawTextInRect:rect]; // fallback is never made transparent
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
    if ([self.superview isKindOfClass:SBCPUTextSlotHost.class]) [self.superview setNeedsLayout];
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

// CALayer.frame is derived from bounds/position; fractional 1/3-point values
// can round-trip with a different least-significant bit. Compare/set the
// canonical stored geometry instead, so identical events perform no writes.
static BOOL SBCPUSetSharedLayerLayout(CALayer *layer, CGRect bounds, CGPoint position) {
    BOOL changed = NO;
    if (!CGRectEqualToRect(layer.bounds, bounds)) { layer.bounds = bounds; changed = YES; }
    if (!CGPointEqualToPoint(layer.position, position)) { layer.position = position; changed = YES; }
    return changed;
}
static BOOL SBCPUSetSharedLayerGeometry(CALayer *layer, CGRect frame) {
    return SBCPUSetSharedLayerLayout(layer, (CGRect){CGPointZero, frame.size},
        CGPointMake(frame.origin.x + frame.size.width*layer.anchorPoint.x,
            frame.origin.y + frame.size.height*layer.anchorPoint.y));
}

@implementation SBCPUTextSlotHost {
    BOOL _sbcpuLiveInversionRequested;
    BOOL _sbcpuSharedRejected;
    CALayer *_sbcpuBackdrop;
    CALayer *_sbcpuMask;
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    CGFloat _sbcpuTestScale;
#endif
}

- (void)sbcpu_syncSharedBackdrop {
    BOOL visible = _sbcpuLiveInversionRequested && self.window && !CGRectIsEmpty(self.bounds);
    for (UIView *v = self; visible && v; v = v.superview)
        visible = !v.hidden && v.alpha > 0.01;
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
#ifdef SBCPU_TEXT_BACKDROP_TESTING
    if (_sbcpuTestScale > 0) scale = _sbcpuTestScale;
#endif
    BOOL supported = !_sbcpuSharedRejected && scale > 0 && isfinite(scale);
    CGRect region = CGRectNull;
    NSMutableArray *slots = [NSMutableArray array], *masks = [NSMutableArray array];
    BOOL changed = NO, activate = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        // Prepare all glyphs BEFORE suppressing any original label. A failed
        // allocation/probe must never leave a partly converted, invisible HUD.
        for (UIView *view in self.subviews) {
            if (!visible || !supported || ![view isKindOfClass:SBCPUCapsuleBackdropLabel.class]) continue;
            SBCPUCapsuleBackdropLabel *slot = (id)view;
            if (slot.hidden || !slot.text.length || CGRectIsEmpty(slot.bounds)) continue;
            if (!CGAffineTransformIsIdentity(slot.transform) || slot.alpha != 1 ||
                !CGPointEqualToPoint(slot.bounds.origin, CGPointZero) ||
                !CGPointEqualToPoint(slot.layer.anchorPoint, CGPointMake(0.5,0.5)) ||
                !CGRectContainsRect(self.bounds, slot.frame)) { supported = NO; break; }
            CGRect ink = CGRectNull;
            CALayer *mask = [slot sbcpu_prepareSharedMaskAtScale:scale ink:&ink changed:&changed];
            if (!mask) { supported = NO; break; }
            [slots addObject:slot]; [masks addObject:mask];
            if (!CGRectIsNull(ink)) region = CGRectUnion(region,
                CGRectOffset(ink, slot.frame.origin.x, slot.frame.origin.y));
        }
        activate = visible && supported && !CGRectIsNull(region);
        if (activate) {
            // A single physical pixel protects antialiasing. Round outward in
            // host coordinates, preserving exact child positions under rotation.
            CGFloat pad = 1.0 / scale;
            region = CGRectInset(region, -pad, -pad);
            CGFloat x = floor(CGRectGetMinX(region)*scale)/scale;
            CGFloat y = floor(CGRectGetMinY(region)*scale)/scale;
            region = CGRectMake(x, y, ceil(CGRectGetMaxX(region)*scale)/scale-x,
                ceil(CGRectGetMaxY(region)*scale)/scale-y);
            region = CGRectIntersection(region, self.bounds);
            if (!_sbcpuBackdrop) {
                _sbcpuBackdrop = SBCPUCreateLiveTextBackdrop(SBCPUSharedBlurRadius, YES);
                if (!_sbcpuBackdrop) _sbcpuSharedRejected = YES;
                else {
                    _sbcpuBackdrop.anchorPoint = CGPointZero;
                    _sbcpuMask = [CALayer layer];
                    _sbcpuMask.anchorPoint = CGPointZero;
                    _sbcpuBackdrop.mask = _sbcpuMask;
#ifdef SBCPU_TEXT_BACKDROP_TESTING
                    gSBCPUBackdropTestCounters.sharedCreations++;
#endif
                }
            }
            activate = _sbcpuBackdrop != nil && _sbcpuMask != nil && _sbcpuBackdrop.mask == _sbcpuMask;
            if (!activate) _sbcpuSharedRejected = YES;
        }
        if (activate) {
            if (SBCPUSetSharedLayerGeometry(_sbcpuBackdrop, region)) changed = YES;
            // Keep all child coordinates in ORIGINAL host space. Moving each
            // fractional child relative to a union origin changes rounding in
            // Core Animation's rasterization matrix (even at 1/255 alpha).
            if (SBCPUSetSharedLayerLayout(_sbcpuMask, region, CGPointZero)) changed = YES;
            if (_sbcpuMask.contentsScale != scale) { _sbcpuMask.contentsScale = scale; changed = YES; }
            // Detach any per-label mask ownership before reparenting native
            // alpha layers. The catch/finally path restores ALL labels on error.
            for (SBCPUCapsuleBackdropLabel *slot in slots) [slot sbcpu_useSharedGlyph];
            if (![_sbcpuMask.sublayers isEqualToArray:masks]) {
                // Restore view order after hidden/remove/insert transitions.
                _sbcpuMask.sublayers = masks; changed = YES;
            }
            for (NSUInteger i = 0; i < slots.count; i++) {
                SBCPUCapsuleBackdropLabel *slot = slots[i]; CALayer *mask = masks[i];
                if (SBCPUSetSharedLayerLayout(mask, slot.bounds, slot.center)) changed = YES;
                if (mask.superlayer != _sbcpuMask) { [_sbcpuMask addSublayer:mask]; changed = YES; }
            }
            for (UIView *view in self.subviews) {
                if (![view isKindOfClass:SBCPUCapsuleBackdropLabel.class] || [slots containsObject:view]) continue;
                [(SBCPUCapsuleBackdropLabel *)view sbcpu_leaveSharedMask];
                [(SBCPUCapsuleBackdropLabel *)view setRealtimeInvertEnabled:NO];
            }
            if (!_sbcpuBackdrop.superlayer) [self.layer addSublayer:_sbcpuBackdrop];
        }
    } @catch (__unused NSException *exception) {
        // Shared errors do not poison the mem5 factory's independent probe.
        _sbcpuSharedRejected = YES; activate = NO;
    } @finally {
        if (!activate) {
            [_sbcpuBackdrop removeFromSuperlayer];
            for (UIView *view in self.subviews) {
                if (![view isKindOfClass:SBCPUCapsuleBackdropLabel.class]) continue;
                SBCPUCapsuleBackdropLabel *slot = (id)view;
                [slot sbcpu_leaveSharedMask];
                slot.realtimeInvertEnabled = visible && !slot.hidden && slot.text.length > 0 && !CGRectIsEmpty(slot.bounds);
            }
            if (_sbcpuSharedRejected) { _sbcpuBackdrop.mask = nil; _sbcpuBackdrop.filters = nil; _sbcpuBackdrop = nil; _sbcpuMask = nil; }
        }
#ifdef SBCPU_TEXT_BACKDROP_TESTING
        if (changed && activate) gSBCPUBackdropTestCounters.sharedMaskWrites++;
#else
        (void)changed;
#endif
        [CATransaction commit];
    }
}

- (void)sbcpu_refreshLiveInversionVisibility { [self sbcpu_syncSharedBackdrop]; }
- (void)sbcpu_setLiveInversionRequested:(BOOL)requested {
    _sbcpuLiveInversionRequested = requested;
    [self sbcpu_syncSharedBackdrop];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self sbcpu_syncSharedBackdrop];
}
- (void)setHidden:(BOOL)hidden {
    if (self.hidden == hidden) return;
    [super setHidden:hidden];
    [self sbcpu_syncSharedBackdrop];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self sbcpu_syncSharedBackdrop];
    else [self setNeedsLayout];
}
- (void)willRemoveSubview:(UIView *)view {
    [super willRemoveSubview:view];
    if ([view isKindOfClass:SBCPUCapsuleBackdropLabel.class]) {
        [(SBCPUCapsuleBackdropLabel *)view sbcpu_leaveSharedMask];
        [self setNeedsLayout];
    }
}
#ifdef SBCPU_TEXT_BACKDROP_TESTING
- (void)sbcpu_testSyncSharedAtScale:(CGFloat)scale {
    _sbcpuTestScale = scale;
    [self sbcpu_syncSharedBackdrop];
}
- (CALayer *)sbcpu_testSharedBackdrop { return _sbcpuBackdrop.superlayer ? _sbcpuBackdrop : nil; }
- (void)sbcpu_testRejectSharedBackdrop { _sbcpuSharedRejected = YES; [self sbcpu_syncSharedBackdrop]; }
#endif
@end
