#import "SBCPUPeachDockConfig.h"
#import "SBCPUPeachDockEdgeTransition.h"
#import "SBCPUPeachDockEdgeTransitionGeometry.h"
#import <Accelerate/Accelerate.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "SBCPUPeachDockDockInteractionState.h"

static char SBCPUPeachDockEdgeControllerKey;
static const CGFloat SBCPUPeachDockEdgeBlurRadius = 5.0;
static const CGFloat SBCPUPeachDockEdgeSnapshotPadding = 16.0;
static const NSUInteger SBCPUPeachDockEdgeMaximumSamples = 12;

@class SBCPUPeachDockEdgeTransition;
@interface SBCPUPeachDockEdgeDisplayLinkProxy : NSObject
@property (nonatomic, weak) SBCPUPeachDockEdgeTransition *owner;
- (void)tick:(CADisplayLink *)link;
@end

@interface SBCPUPeachDockEdgeSample : NSObject
@property (nonatomic, weak) UIView *iconView;
@property (nonatomic, weak) id capturedIdentity;
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) UIImageView *sharpImageView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) CALayer *sourceMask;
@property (nonatomic, strong) CALayer *hidingMask;
@property (nonatomic) BOOL sourceReplaced;
@property (nonatomic) CGSize capturedSize;
@property (nonatomic) BOOL pending;
@property (nonatomic) CFTimeInterval capturedAt;
@property (nonatomic) CFTimeInterval retryAfter;
@property (nonatomic) CGFloat padding;
@property (nonatomic) CGFloat sharpPadding;
- (void)restoreSource;
- (void)hideSource;
@end
@implementation SBCPUPeachDockEdgeSample
- (void)restoreSource {
    UIView *icon = self.iconView;
    if (self.sourceReplaced && icon.layer.mask == self.hidingMask)
        icon.layer.mask = self.sourceMask;
    self.sourceReplaced = NO;
    self.sourceMask = nil;
    self.container.hidden = YES;
}
- (void)hideSource {
    UIView *icon = self.iconView;
    if (!icon) return;
    if (!self.sourceReplaced) {
        self.sourceMask = icon.layer.mask;
        self.sourceReplaced = YES;
    }
    self.hidingMask.frame = icon.bounds;
    icon.layer.mask = self.hidingMask;
}
- (void)dealloc {
    [self restoreSource];
}
@end

@interface SBCPUPeachDockEdgeTransition () {
    __weak UIView *_listView;
    __weak UIScrollView *_scrollView;
    __weak UIView *_contentView;
    __weak UIView *_clipView;
    UIView *_sharpViewport;
    UIView *_blurOverlay;
    NSMutableArray<SBCPUPeachDockEdgeSample *> *_samples;
    CADisplayLink *_displayLink;
    SBCPUPeachDockEdgeDisplayLinkProxy *_displayProxy;
    BOOL _active;
    BOOL _springing;
    BOOL _iconEditing;
    BOOL _wasEditing;
    CFTimeInterval _editingResumeAfter;
    NSUInteger _captureGeneration;
    BOOL _invalidated;
    BOOL _captureScheduled;
    BOOL _rendering;
    BOOL _lastFrameHadEffect;
    CGFloat _effectGain;
    CFTimeInterval _lastTickTime;
    CGPoint _lastDisplayedOffset;
    NSUInteger _stableFrames;
}
- (void)displayTick:(CADisplayLink *)link;
- (void)renderFrame;
- (void)stopTracking;
@end

@implementation SBCPUPeachDockEdgeDisplayLinkProxy
- (void)tick:(CADisplayLink *)link {
    SBCPUPeachDockEdgeTransition *owner = self.owner;
    if (owner) [owner displayTick:link];
    else [link invalidate];
}
@end

static id SBCPUPeachDockEdgeIconIdentity(UIView *view) {
    SEL selector = sel_registerName("icon");
    id model = [view respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(view, selector) : nil;
    return model ?: view;
}

BOOL SBCPUPeachDockIconEditingActive(void) {
    Class controllerClass = objc_getClass("SBIconController");
    SEL sharedSelector = sel_registerName("sharedInstance");
    SEL editingSelector = sel_registerName("isEditing");
    Method shared = class_getClassMethod(controllerClass, sharedSelector);
    char result[8] = {0};
    if (!shared || method_getNumberOfArguments(shared) != 2) return NO;
    method_getReturnType(shared, result, sizeof(result));
    if (result[0] != '@') return NO;
    id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, sharedSelector);
    Method getter = class_getInstanceMethod(object_getClass(controller), editingSelector);
    if (!getter || method_getNumberOfArguments(getter) != 2) return NO;
    method_getReturnType(getter, result, sizeof(result));
    if (result[0] != 'B' && result[0] != 'c') return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(controller, editingSelector);
}

static dispatch_queue_t SBCPUPeachDockEdgeRenderingQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("leo.infinidock16.edge-images", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void SBCPUPeachDockEdgeFreePixels(void *info, const void *data, size_t size) {
    (void)info; (void)size;
    free((void *)data);
}

static UIImage *SBCPUPeachDockEdgeBlurImage(UIImage *image, CGFloat *padding) {
    // Three separable box approximations give a Gaussian-like soft edge. This
    // uses only CPU vImage, with transparent padding and premultiplied channels:
    // no CIContext, Metal/EAGL context, private filters, or per-frame rendering.
    CGImageRef input = image.CGImage;
    if (!input || image.scale <= 0) return nil;
    CGFloat radius = SBCPUPeachDockEdgeBlurRadius * image.scale;
    uint32_t kernel = MAX((uint32_t)3, ((uint32_t)ceil(radius * 2.0)) | 1U);
    size_t pad = (kernel / 2) * 3;
    size_t inputWidth = CGImageGetWidth(input), inputHeight = CGImageGetHeight(input);
    if (!inputWidth || !inputHeight || inputWidth > 1024 || inputHeight > 1024) return nil;
    size_t width = inputWidth + pad * 2, height = inputHeight + pad * 2;
    size_t rowBytes = (width * 4 + 15) & ~(size_t)15;
    size_t bytes = rowBytes * height;
    void *first = calloc(1, bytes), *second = calloc(1, bytes);
    if (!first || !second) { free(first); free(second); return nil; }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo format = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
    CGContextRef bitmap = CGBitmapContextCreate(first, width, height, 8, rowBytes, colorSpace, format);
    if (!bitmap) {
        CGColorSpaceRelease(colorSpace); free(first); free(second); return nil;
    }
    CGContextDrawImage(bitmap, CGRectMake(pad, pad, inputWidth, inputHeight), input);
    CGContextRelease(bitmap);
    vImage_Buffer a = {first, height, width, rowBytes};
    vImage_Buffer b = {second, height, width, rowBytes};
    vImage_Error error = vImageBoxConvolve_ARGB8888(&a, &b, NULL, 0, 0, kernel, kernel, NULL, kvImageEdgeExtend);
    if (error == kvImageNoError)
        error = vImageBoxConvolve_ARGB8888(&b, &a, NULL, 0, 0, kernel, kernel, NULL, kvImageEdgeExtend);
    if (error == kvImageNoError)
        error = vImageBoxConvolve_ARGB8888(&a, &b, NULL, 0, 0, kernel, kernel, NULL, kvImageEdgeExtend);
    free(first);
    if (error != kvImageNoError) { CGColorSpaceRelease(colorSpace); free(second); return nil; }
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, second, bytes, SBCPUPeachDockEdgeFreePixels);
    if (!provider) { CGColorSpaceRelease(colorSpace); free(second); return nil; }
    CGImageRef output = CGImageCreate(width, height, 8, 32, rowBytes, colorSpace, format,
                                    provider, NULL, YES, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    if (!output) return nil;
    UIImage *result = [UIImage imageWithCGImage:output scale:image.scale orientation:UIImageOrientationUp];
    CGImageRelease(output);
    *padding = pad / image.scale;
    return result;
}

@implementation SBCPUPeachDockEdgeTransition

// Pure ownership query: never create a controller, render, or change edit state.
// Only our current associated controller and exact wrapper identity are trusted.
+ (BOOL)sbcpu_peach_dock_listView:(UIView *)listView
       ownsScrollView:(UIScrollView *)scrollView
          contentView:(UIView *)contentView
             clipView:(UIView *)clipView {
    if (!NSThread.isMainThread || !listView || !scrollView || !contentView || !clipView) return NO;
    @try {
        SBCPUPeachDockEdgeTransition *controller = objc_getAssociatedObject(listView, &SBCPUPeachDockEdgeControllerKey);
        if (![controller isKindOfClass:SBCPUPeachDockEdgeTransition.class] || controller->_invalidated ||
            controller->_listView != listView || controller->_scrollView != scrollView ||
            controller->_contentView != contentView || controller->_clipView != clipView) return NO;
        UIView *wrapper = controller->_sharpViewport;
        return wrapper && contentView.superview == scrollView && scrollView.superview == wrapper &&
            wrapper.superview == clipView && clipView.superview == listView;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

+ (instancetype)transitionForListView:(UIView *)listView
                          scrollView:(UIScrollView *)scrollView
                         contentView:(UIView *)contentView
                            clipView:(UIView *)clipView {
    SBCPUPeachDockEdgeTransition *old = objc_getAssociatedObject(listView, &SBCPUPeachDockEdgeControllerKey);
    if (old && !old->_invalidated && old->_scrollView == scrollView &&
        old->_contentView == contentView && old->_clipView == clipView) return old;
    [old invalidate];
    SBCPUPeachDockEdgeTransition *controller = [self new];
    controller->_listView = listView;
    controller->_scrollView = scrollView;
    controller->_contentView = contentView;
    controller->_clipView = clipView;
    controller->_samples = [NSMutableArray array];
    controller->_sharpViewport = [[UIView alloc] initWithFrame:clipView.bounds];
    controller->_sharpViewport.backgroundColor = UIColor.clearColor;
    controller->_blurOverlay = [[UIView alloc] initWithFrame:clipView.bounds];
    controller->_blurOverlay.backgroundColor = UIColor.clearColor;
    controller->_blurOverlay.userInteractionEnabled = NO;
    controller->_blurOverlay.isAccessibilityElement = NO;
    controller->_blurOverlay.accessibilityElementsHidden = YES;
    controller->_blurOverlay.hidden = YES;
    controller->_lastDisplayedOffset = CGPointMake(NAN, NAN);
    [clipView insertSubview:controller->_sharpViewport atIndex:0];
    [controller->_sharpViewport addSubview:scrollView];
    [clipView addSubview:controller->_blurOverlay];
    objc_setAssociatedObject(listView, &SBCPUPeachDockEdgeControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return controller;
}

- (void)dealloc {
    [_displayLink invalidate];
    for (SBCPUPeachDockEdgeSample *sample in _samples) [sample restoreSource];
}

- (BOOL)editingSuppressed {
    BOOL editing = NO;
    @try {
        // Re-read on every render/query: pushed flags can lag local edit entry
        // or exit. A valid local NO is just as authoritative as local YES.
        if (!SBCPUPeachDockDockReadEditing(_listView, &editing))
            editing = _iconEditing || SBCPUPeachDockIconEditingActive();
    } @catch (__unused NSException *exception) {
        // Unknown/throwing controller probes retain the legacy explicit flag.
        editing = _iconEditing;
    }
    if (editing && !_wasEditing) {
        _wasEditing = YES;
        _springing = NO;
        ++_captureGeneration;
        _captureScheduled = NO;
        [self stopTracking];
        for (SBCPUPeachDockEdgeSample *sample in _samples) [sample.container removeFromSuperview];
        [_samples removeAllObjects];
    } else if (!editing && _wasEditing) {
        _wasEditing = NO;
        _editingResumeAfter = CACurrentMediaTime() + 0.20;
    }
    return editing || CACurrentMediaTime() < _editingResumeAfter;
}

- (BOOL)effectsAllowed {
    return SBCPUPeachDockEffects() && ![self editingSuppressed];
}

- (void)layout {
    if (_invalidated || !NSThread.isMainThread) return;
    UIView *clip = _clipView;
    if (!clip || !_scrollView || !_contentView) { [self invalidate]; return; }
    if (!isfinite(clip.bounds.size.width) || !isfinite(clip.bounds.size.height) ||
        clip.bounds.size.width <= 0 || clip.bounds.size.height <= 0) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _sharpViewport.frame = clip.bounds;
    _blurOverlay.frame = clip.bounds;
    [CATransaction commit];
    [self renderFrame];
}

- (CGPoint)displayedOffset {
    UIScrollView *scroll = _scrollView;
    CALayer *presentation = _active ? scroll.layer.presentationLayer : nil;
    CGPoint offset = presentation ? presentation.bounds.origin : scroll.contentOffset;
    return isfinite(offset.x) && isfinite(offset.y) ? offset : CGPointZero;
}

- (void)beginInteraction {
    if (_invalidated || ![self effectsAllowed]) { [self stopTracking]; return; }
    if (!_active) {
        // Refresh cached badge/icon imagery at the next gesture, never per tick.
        // The real icon is restored before discarding a cached replacement.
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (SBCPUPeachDockEdgeSample *sample in _samples) {
            [sample restoreSource];
            if (!sample.pending && CACurrentMediaTime() - sample.capturedAt > 0.5) {
                sample.sharpImageView.image = nil;
                sample.imageView.image = nil;
            }
        }
        [CATransaction commit];
        _active = YES;
        _effectGain = 1;
        _lastTickTime = 0;
        _stableFrames = 0;
        _lastDisplayedOffset = CGPointMake(NAN, NAN);
        _displayProxy = [SBCPUPeachDockEdgeDisplayLinkProxy new];
        _displayProxy.owner = self;
        _displayLink = [CADisplayLink displayLinkWithTarget:_displayProxy selector:@selector(tick:)];
        _displayLink.preferredFramesPerSecond = UIScreen.mainScreen.maximumFramesPerSecond;
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    [self renderFrame];
}

- (void)setIconEditing:(BOOL)editing {
    if (_invalidated || _iconEditing == editing) return;
    _iconEditing = editing;
    (void)[self editingSuppressed];
}

- (void)scrollDidChange {
    [self beginInteraction];
}

- (void)endInteraction {
    // Do not immediately remove the masks: the model offset can reach the end
    // before a UIViewPropertyAnimator's presentation layer finishes its spring.
    if (_active) [self renderFrame];
}

- (void)beginSpring {
    _springing = YES;
    [self beginInteraction];
}

- (void)endSpring {
    _springing = NO;
    [self endInteraction];
}

- (void)stopTracking {
    [_displayLink invalidate];
    _displayLink = nil;
    _displayProxy = nil;
    _active = NO;
    _stableFrames = 0;
    _effectGain = 0;
    _lastTickTime = 0;
    _lastFrameHadEffect = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (SBCPUPeachDockEdgeSample *sample in _samples) [sample restoreSource];
    _blurOverlay.hidden = YES;
    [CATransaction commit];
}

- (void)displayTick:(CADisplayLink *)link {
    (void)link;
    UIScrollView *scroll = _scrollView;
    if (_invalidated || !scroll || !_clipView.window || ![self effectsAllowed]) {
        [self stopTracking]; return;
    }
    CGPoint offset = [self displayedOffset];
    BOOL stable = isfinite(_lastDisplayedOffset.x) &&
        fabs(offset.x - _lastDisplayedOffset.x) < 0.05 &&
        fabs(offset.y - _lastDisplayedOffset.y) < 0.05 &&
        fabs(offset.x - scroll.contentOffset.x) < 0.1;
    _stableFrames = stable ? _stableFrames + 1 : 0;
    _lastDisplayedOffset = offset;
    BOOL finished = !_springing && !scroll.dragging && !scroll.tracking &&
                    !scroll.decelerating && _stableFrames >= 3;
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval dt = _lastTickTime > 0 ? fmin(0.05, fmax(0, now - _lastTickTime)) : 1.0 / 60.0;
    _lastTickTime = now;
    // Paging arrives at a neutral profile naturally. In continuous mode an
    // arbitrary resting offset can leave an edge icon small: ease it back to
    // the live source over 160 ms instead of suddenly restoring its full size.
    if (finished) _effectGain = fmax(0, _effectGain - dt / 0.16);
    else _effectGain = fmin(1, _effectGain + dt / 0.16);
    [self renderFrame];
    if (finished && (!_lastFrameHadEffect || _effectGain <= 0)) [self stopTracking];
}

- (SBCPUPeachDockEdgeSample *)sampleForIcon:(UIView *)icon {
    for (SBCPUPeachDockEdgeSample *sample in _samples) if (sample.iconView == icon) return sample;
    if (_samples.count >= SBCPUPeachDockEdgeMaximumSamples) return nil;
    SBCPUPeachDockEdgeSample *sample = [SBCPUPeachDockEdgeSample new];
    sample.iconView = icon;
    sample.container = [UIView new];
    sample.container.userInteractionEnabled = NO;
    sample.container.accessibilityElementsHidden = YES;
    sample.container.hidden = YES;
    sample.imageView = [UIImageView new];
    sample.sharpImageView = [UIImageView new];
    for (UIImageView *imageView in @[sample.imageView, sample.sharpImageView]) {
        imageView.userInteractionEnabled = NO;
        imageView.isAccessibilityElement = NO;
        imageView.contentMode = UIViewContentModeScaleToFill;
        [sample.container addSubview:imageView];
    }
    sample.hidingMask = [CALayer layer];
    sample.hidingMask.opacity = 0;
    [_blurOverlay addSubview:sample.container];
    [_samples addObject:sample];
    return sample;
}

- (void)requestImageForSample:(SBCPUPeachDockEdgeSample *)sample {
    if (![self effectsAllowed]) return;
    UIView *icon = sample.iconView;
    CGSize size = icon.bounds.size;
    if (!icon || !icon.window || size.width <= 0 || size.height <= 0 ||
        size.width > 160 || size.height > 200 || sample.pending ||
        sample.retryAfter > CACurrentMediaTime()) return;
    BOOL sameSize = CGSizeEqualToSize(size, sample.capturedSize);
    if (sameSize && sample.sharpImageView.image &&
        (_active || CACurrentMediaTime() - sample.capturedAt < 0.5)) return;
    if (_captureScheduled) return;
    NSUInteger pending = 0;
    for (SBCPUPeachDockEdgeSample *entry in _samples) pending += entry.pending;
    if (pending >= 2) return;
    _captureScheduled = YES;
    sample.pending = YES;
    NSUInteger generation = _captureGeneration;
    __weak SBCPUPeachDockEdgeTransition *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SBCPUPeachDockEdgeTransition *owner = weakSelf;
        UIView *view = sample.iconView;
        if (!owner || owner->_invalidated || ![owner effectsAllowed] ||
            generation != owner->_captureGeneration || !view.window ||
            ![owner->_samples containsObject:sample]) {
            if (owner && generation == owner->_captureGeneration) owner->_captureScheduled = NO;
            sample.pending = NO;
            return;
        }
        CGSize capturedSize = view.bounds.size;
        if (!isfinite(capturedSize.width) || !isfinite(capturedSize.height) ||
            capturedSize.width <= 0 || capturedSize.height <= 0 ||
            capturedSize.width > 160 || capturedSize.height > 200) {
            owner->_captureScheduled = NO;
            sample.pending = NO;
            sample.retryAfter = CACurrentMediaTime() + 1.0;
            return;
        }
        CGFloat scale = MIN(UIScreen.mainScreen.scale, 2.0);
        UIImage *image = nil;
        BOOL beganContext = NO;
        CALayer *maskBeforeCapture = view.layer.mask;
        BOOL ownMask = sample.sourceReplaced && maskBeforeCapture == sample.hidingMask;
        CALayer *capturedMask = ownMask ? sample.sourceMask : maskBeforeCapture;
        id capturedIdentity = SBCPUPeachDockEdgeIconIdentity(view);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        @try {
            // Never snapshot our own invisible mask. The original mask, if any,
            // is part of the captured image and is restored on every exit path.
            if (ownMask) view.layer.mask = sample.sourceMask;
            CGSize snapshotSize = CGSizeMake(capturedSize.width + 2 * SBCPUPeachDockEdgeSnapshotPadding,
                                             capturedSize.height + 2 * SBCPUPeachDockEdgeSnapshotPadding);
            UIGraphicsBeginImageContextWithOptions(snapshotSize, NO, scale);
            beganContext = YES;
            CGContextRef cg = UIGraphicsGetCurrentContext();
            if (cg) {
                CGContextTranslateCTM(cg, SBCPUPeachDockEdgeSnapshotPadding - view.bounds.origin.x,
                                     SBCPUPeachDockEdgeSnapshotPadding - view.bounds.origin.y);
                [view.layer renderInContext:cg];
                image = UIGraphicsGetImageFromCurrentImageContext();
            }
        } @catch (__unused NSException *exception) {
            // Third-party icon renderers can refuse software snapshots.
        } @finally {
            if (beganContext) UIGraphicsEndImageContext();
            if (ownMask && view.layer.mask == sample.sourceMask) view.layer.mask = maskBeforeCapture;
            [CATransaction commit];
        }
        owner->_captureScheduled = NO;
        if (!image.CGImage) {
            sample.pending = NO;
            sample.retryAfter = CACurrentMediaTime() + 1.0;
            return;
        }
        // Scale the complete icon immediately; blur is a cached refinement.
        sample.sharpImageView.image = image;
        sample.imageView.image = nil;
        sample.padding = SBCPUPeachDockEdgeSnapshotPadding;
        sample.sharpPadding = SBCPUPeachDockEdgeSnapshotPadding;
        sample.capturedSize = capturedSize;
        sample.capturedIdentity = capturedIdentity;
        sample.capturedAt = CACurrentMediaTime();
        [owner renderFrame];
        dispatch_async(SBCPUPeachDockEdgeRenderingQueue(), ^{
            @autoreleasepool {
                CGFloat padding = 0;
                UIImage *blurred = SBCPUPeachDockEdgeBlurImage(image, &padding);
                dispatch_async(dispatch_get_main_queue(), ^{
                    SBCPUPeachDockEdgeTransition *current = weakSelf;
                    sample.pending = NO;
                    if (!current || current->_invalidated || ![current effectsAllowed] ||
                        generation != current->_captureGeneration ||
                        ![current->_samples containsObject:sample]) return;
                    UIView *currentIcon = sample.iconView;
                    CALayer *currentMask = sample.sourceReplaced && currentIcon.layer.mask == sample.hidingMask
                        ? sample.sourceMask : currentIcon.layer.mask;
                    if (SBCPUPeachDockEdgeIconIdentity(currentIcon) != capturedIdentity || currentMask != capturedMask) {
                        if (sample.sharpImageView.image == image) {
                            sample.sharpImageView.image = nil;
                            sample.imageView.image = nil;
                        }
                        [current renderFrame];
                        return;
                    }
                    if (blurred && CGSizeEqualToSize(currentIcon.bounds.size, capturedSize)) {
                        sample.imageView.image = blurred;
                        sample.capturedSize = capturedSize;
                        sample.padding = SBCPUPeachDockEdgeSnapshotPadding + padding;
                    } else sample.retryAfter = CACurrentMediaTime() + 1.0;
                    [current renderFrame];
                });
            }
        });
    });
}

- (void)renderFrame {
    if (_invalidated || _rendering || !NSThread.isMainThread) return;
    if (![self effectsAllowed]) { [self stopTracking]; return; }
    UIView *content = _contentView, *clip = _clipView;
    UIScrollView *scroll = _scrollView;
    CGFloat width = CGRectGetWidth(clip.bounds), height = CGRectGetHeight(clip.bounds);
    if (!content || !scroll || !clip.window || !isfinite(width) || !isfinite(height) ||
        width <= 0 || height <= 0) { [self stopTracking]; return; }
    if (![self effectsAllowed]) { [self stopTracking]; return; }
    _rendering = YES;
    CGPoint offset = [self displayedOffset];
    CGFloat neutralDistance = width * 0.5;
    Class iconClass = objc_getClass("SBIconView");
    NSMutableArray<UIView *> *nearby = [NSMutableArray arrayWithCapacity:8];
    for (UIView *view in content.subviews) {
        if (!iconClass || ![view isKindOfClass:iconClass] || view.hidden || view.alpha < 0.01) continue;
        CGRect rect = [content convertRect:view.bounds fromView:view];
        if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) ||
            !isfinite(rect.size.width) || !isfinite(rect.size.height) ||
            rect.size.width <= 0 || rect.size.height <= 0) continue;
        neutralDistance = MIN(neutralDistance, rect.size.width * 0.9);
        CGFloat pageWidth = CGRectGetWidth(scroll.bounds);
        if (isfinite(pageWidth) && pageWidth > 0) {
            CGFloat canonicalX = fmod(rect.origin.x + content.frame.origin.x, pageWidth);
            if (canonicalX < 0) canonicalX += pageWidth;
            canonicalX += scroll.frame.origin.x;
            neutralDistance = SBCPUPeachDockEdgeRestingDistance(neutralDistance, width, canonicalX, rect.size.width);
        }
        CGFloat x = SBCPUPeachDockEdgeViewportX(rect.origin.x, content.frame.origin.x, scroll.frame.origin.x, offset.x);
        if (x + rect.size.width >= -100 && x <= width + 100) [nearby addObject:view];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (SBCPUPeachDockEdgeSample *sample in [_samples copy]) {
        if (!sample.iconView || ![nearby containsObject:sample.iconView]) {
            [sample restoreSource];
            [sample.container removeFromSuperview];
            [_samples removeObject:sample];
        }
    }
    _lastFrameHadEffect = NO;
    for (UIView *icon in nearby) {
        SBCPUPeachDockEdgeSample *sample = [self sampleForIcon:icon];
        if (!sample) continue;
        // If a different tweak changed its mask, preserve that change and refresh
        // the snapshot. Never restore a stale mask over another owner's layer.
        if ((sample.sourceReplaced && icon.layer.mask != sample.hidingMask) ||
            (sample.sharpImageView.image && sample.capturedIdentity != SBCPUPeachDockEdgeIconIdentity(icon))) {
            [sample restoreSource];
            sample.sharpImageView.image = nil;
            sample.imageView.image = nil;
        }
        [self requestImageForSample:sample];
        CGRect rect = [content convertRect:icon.bounds fromView:icon];
        rect.origin.x = SBCPUPeachDockEdgeViewportX(rect.origin.x, content.frame.origin.x, scroll.frame.origin.x, offset.x);
        rect.origin.y += content.frame.origin.y + scroll.frame.origin.y - offset.y;
        CGFloat progress = SBCPUPeachDockEdgeIconProgress(CGRectGetMidX(rect), width, rect.size.width, neutralDistance);
        progress *= _active ? _effectGain : 0;
        BOOL ready = sample.sharpImageView.image && CGSizeEqualToSize(sample.capturedSize, icon.bounds.size);
        if (!ready || progress <= 0.0001) {
            [sample restoreSource];
            continue;
        }
        CGFloat scale = SBCPUPeachDockEdgeIconScale(progress);
        CGFloat blurMix = sample.imageView.image ? SBCPUPeachDockEdgeIconBlurMix(progress) : 0;
        // Scale only the visual replacement, about the original icon center.
        // The SBIconView frame/bounds/transform, gesture target and model layout
        // are untouched; a transparent layer mask suppresses only its drawing.
        CGFloat padX = sample.padding * rect.size.width / sample.capturedSize.width;
        CGFloat padY = sample.padding * rect.size.height / sample.capturedSize.height;
        CGSize canvas = CGSizeMake(rect.size.width + 2 * padX, rect.size.height + 2 * padY);
        sample.container.bounds = (CGRect){CGPointZero, canvas};
        sample.container.center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
        sample.container.transform = CGAffineTransformMakeScale(scale, scale);
        sample.imageView.frame = sample.container.bounds;
        CGFloat sharpPadX = sample.sharpPadding * rect.size.width / sample.capturedSize.width;
        CGFloat sharpPadY = sample.sharpPadding * rect.size.height / sample.capturedSize.height;
        sample.sharpImageView.frame = CGRectMake(padX - sharpPadX, padY - sharpPadY,
            rect.size.width + 2 * sharpPadX, rect.size.height + 2 * sharpPadY);
        sample.imageView.alpha = blurMix;
        sample.sharpImageView.alpha = 1 - blurMix;
        sample.container.hidden = NO;
        [sample hideSource];
        _lastFrameHadEffect = YES;
    }
    _blurOverlay.hidden = !_active;
    [CATransaction commit];
    _rendering = NO;
}

- (void)invalidate {
    if (_invalidated) return;
    _invalidated = YES;
    [self stopTracking];
    if (_scrollView.superview == _sharpViewport && _clipView) {
        [_clipView insertSubview:_scrollView atIndex:0];
    }
    [_sharpViewport removeFromSuperview];
    [_blurOverlay removeFromSuperview];
    [_samples removeAllObjects];
}
@end
