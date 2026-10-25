// Included once by Tweak.m. Native query points are list-space; icon parents
// are our scroll content. Mapping is restricted to editing, never unlock layout.
#import "SBCPUPeachDockDockDropGeometry.h"
#import <QuartzCore/QuartzCore.h>
#include <string.h>
static char SBCPUPeachDockDropLayoutDepthKey;
static char SBCPUPeachDockDropNativeQueryDepthKey;
static NSUInteger SBCPUPeachDockDropLayoutDepth(id list) {
    return [objc_getAssociatedObject(list, &SBCPUPeachDockDropLayoutDepthKey) unsignedIntegerValue];
}
static void SBCPUPeachDockDropSetLayoutDepth(id list, NSUInteger depth) {
    objc_setAssociatedObject(list, &SBCPUPeachDockDropLayoutDepthKey, depth ? @(depth) : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL SBCPUPeachDockDropTypeMatches(const char *actual, const char *expected) {
    if (!actual || !expected) return NO;
    if (!strcmp(actual, expected)) return YES;
    if (actual[0] == '{' && expected[0] == '{') {
        const char *a = strchr(actual, '='), *e = strchr(expected, '=');
        return a && e && !strcmp(a, e);
    }
    return NO;
}
static BOOL SBCPUPeachDockDropMethodMatches(Class cls, SEL selector, const char *result,
                                  const char *const *arguments, NSUInteger count) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != count + 2) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (!SBCPUPeachDockDropTypeMatches(sig.methodReturnType, result)) return NO;
    for (NSUInteger i = 0; i < count; ++i)
        if (!SBCPUPeachDockDropTypeMatches([sig getArgumentTypeAtIndex:i + 2], arguments[i])) return NO;
    return YES;
}
static BOOL SBCPUPeachDockDropHasContent(SBDockIconListView *list) {
    if (!NSThread.isMainThread) return NO;
    UIView *content = SBCPUPeachDockContentView(list);
    if (!content || !SBCPUPeachDockScrollView(list) || ![content isDescendantOfView:list]) return NO;
    // Native center offsets are expressed in list axes. Translation (including
    // scrolling/insets) is supported; don't guess under a scaled/rotated wrapper.
    CGPoint p = [list convertPoint:CGPointZero fromView:content];
    CGPoint x = [list convertPoint:CGPointMake(1, 0) fromView:content];
    CGPoint y = [list convertPoint:CGPointMake(0, 1) fromView:content];
    return isfinite(p.x) && isfinite(p.y) && fabs(x.x - p.x - 1) < 1e-6 &&
        fabs(x.y - p.y) < 1e-6 && fabs(y.x - p.x) < 1e-6 && fabs(y.y - p.y - 1) < 1e-6;
}
static BOOL SBCPUPeachDockDropWantsMapping(SBDockIconListView *list) {
    if (!SBCPUPeachDockDropHasContent(list) ||
        [objc_getAssociatedObject(list, &SBCPUPeachDockDropNativeQueryDepthKey) unsignedIntegerValue] || !SBCPUPeachDockDockInteractionActive(list)) return NO;
    // The page geometry is explicitly LTR. Native RTL reverses both index and
    // fraction; until it is independently adapted, preserve all native answers.
    SEL reversed = sel_registerName("isLayoutReversed");
    if (!SBCPUPeachDockDropMethodMatches(object_getClass(list), reversed, @encode(BOOL), NULL, 0)) return NO;
    @try { return !((BOOL (*)(id, SEL))objc_msgSend)(list, reversed); }
    @catch (__unused NSException *exception) { return NO; }
}
static BOOL SBCPUPeachDockDropNativeCenter(SBDockIconListView *list, SBCPUPeachDockIconCoordinate coordinate,
                                 id metrics, CGPoint *center) {
    SEL selector = @selector(centerForIconCoordinate:metrics:);
    const char *args[] = { @encode(SBCPUPeachDockIconCoordinate), "@" };
    if (!SBCPUPeachDockDropMethodMatches(object_getClass(list), selector, @encode(CGPoint), args, 2)) return NO;
    NSUInteger depth = [objc_getAssociatedObject(list, &SBCPUPeachDockDropNativeQueryDepthKey) unsignedIntegerValue];
    if (depth) return NO;
    BOOL valid = NO;
    objc_setAssociatedObject(list, &SBCPUPeachDockDropNativeQueryDepthKey, @(depth + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        // The real 16.2 center routine also accounts for image-center and content
        // scale. Preserve it instead of assuming bounds.width/2 or a private size
        // getter. Its nested origin query bypasses only OUR forward mapping.
        *center = ((CGPoint (*)(id, SEL, SBCPUPeachDockIconCoordinate, id))objc_msgSend)(list, selector, coordinate, metrics);
        valid = isfinite(center->x) && isfinite(center->y);
    } @catch (__unused NSException *exception) {
        valid = NO;
    } @finally {
        objc_setAssociatedObject(list, &SBCPUPeachDockDropNativeQueryDepthKey, depth ? @(depth) : nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return valid;
}
static CGPoint (*SBCPUPeachDockOriginalNativeOrigin)(SBDockIconListView *, SEL, SBCPUPeachDockIconCoordinate, id, NSUInteger);
static CGPoint SBCPUPeachDockHookNativeOrigin(SBDockIconListView *self, SEL cmd,
                                    SBCPUPeachDockIconCoordinate coordinate, id metrics, NSUInteger options) {
    CGPoint original = SBCPUPeachDockOriginalNativeOrigin(self, cmd, coordinate, metrics, options);
    if ([objc_getAssociatedObject(self, &SBCPUPeachDockDropNativeQueryDepthKey) unsignedIntegerValue] ||
        !SBCPUPeachDockDropWantsMapping(self) || options != 0 || coordinate.row != 1 || coordinate.col < 1 ||
        coordinate.col > (long long)SBCPUPeachDockMaximumDockIcons || !isfinite(original.x) || !isfinite(original.y)) return original;
    double desiredCenter;
    if (!SBCPUPeachDockDropCenterX((unsigned)coordinate.col, (unsigned)SBCPUPeachDockMaximumDockIcons,
                        CGRectGetWidth(SBCPUPeachDockScrollView(self).bounds), SBCPUPeachDockIconPitch(self), &desiredCenter)) return original;
    CGPoint nativeCenter;
    if (!SBCPUPeachDockDropNativeCenter(self, coordinate, metrics, &nativeCenter)) return original;
    UIView *content = SBCPUPeachDockContentView(self);
    CGPoint originInContent = [content convertPoint:original fromView:self];
    CGPoint centerInContent = [content convertPoint:nativeCenter fromView:self];
    originInContent.x += desiredCenter - centerInContent.x;
    if (!isfinite(originInContent.x) || !isfinite(originInContent.y)) return original;
    // Synchronous placement uses the icon's actual content parent. Public-to-
    // SpringBoard center/rect/drag queries outside that scope stay list-space.
    return SBCPUPeachDockDropLayoutDepth(self) ? originInContent :
        [self convertPoint:originInContent fromView:content];
}
static NSUInteger (*SBCPUPeachDockOriginalNativeColumn)(SBDockIconListView *, SEL, CGPoint, id, double *);
static NSUInteger SBCPUPeachDockHookNativeColumn(SBDockIconListView *self, SEL cmd,
                                       CGPoint point, id metrics, double *fraction) {
    NSUInteger nativeColumn = SBCPUPeachDockOriginalNativeColumn(self, cmd, point, metrics, fraction);
    if (!SBCPUPeachDockDropWantsMapping(self) || !isfinite(point.x) || !isfinite(point.y)) return nativeColumn;
    CGPoint contentPoint = [SBCPUPeachDockContentView(self) convertPoint:point fromView:self];
    unsigned column;
    double mappedFraction;
    if (!SBCPUPeachDockDropColumnAtX(contentPoint.x, (unsigned)SBCPUPeachDockMaximumDockIcons,
                          CGRectGetWidth(SBCPUPeachDockScrollView(self).bounds), SBCPUPeachDockIconPitch(self),
                          &column, &mappedFraction)) return nativeColumn;
    if (fraction) *fraction = mappedFraction;
    // SBIconCoordinate.col is 1-based, but columnAtPoint returns a ZERO-based
    // index: native coordinateAtPoint adds 1 after this call (16.2 disassembly).
    return (NSUInteger)column - 1;
}
static void (*SBCPUPeachDockOriginalNativeLayoutIcons)(SBDockIconListView *, SEL, id, NSUInteger);
static void SBCPUPeachDockHookNativeLayoutIcons(SBDockIconListView *self, SEL cmd, id animator, NSUInteger options) {
    NSUInteger depth = SBCPUPeachDockDropLayoutDepth(self);
    SBCPUPeachDockDropSetLayoutDepth(self, depth + 1);
    @try { SBCPUPeachDockOriginalNativeLayoutIcons(self, cmd, animator, options); }
    @finally { SBCPUPeachDockDropSetLayoutDepth(self, depth); }
}
static void (*SBCPUPeachDockOriginalNativeLayoutNow)(SBDockIconListView *, SEL);
static void SBCPUPeachDockHookNativeLayoutNow(SBDockIconListView *self, SEL cmd) {
    NSUInteger depth = SBCPUPeachDockDropLayoutDepth(self);
    SBCPUPeachDockDropSetLayoutDepth(self, depth + 1);
    @try { SBCPUPeachDockOriginalNativeLayoutNow(self, cmd); }
    @finally { SBCPUPeachDockDropSetLayoutDepth(self, depth); }
}
static void (*SBCPUPeachDockOriginalNativeCreate)(SBDockIconListView *, SEL, id);
static void SBCPUPeachDockHookNativeCreate(SBDockIconListView *self, SEL cmd, id icon) {
    NSUInteger depth = SBCPUPeachDockDropLayoutDepth(self);
    SBCPUPeachDockDropSetLayoutDepth(self, depth + 1);
    @try { SBCPUPeachDockOriginalNativeCreate(self, cmd, icon); }
    @finally { SBCPUPeachDockDropSetLayoutDepth(self, depth); }
}
static void (*SBCPUPeachDockOriginalNativeCreateAtIndex)(SBDockIconListView *, SEL, id, NSUInteger);
static void SBCPUPeachDockHookNativeCreateAtIndex(SBDockIconListView *self, SEL cmd, id icon, NSUInteger index) {
    NSUInteger depth = SBCPUPeachDockDropLayoutDepth(self);
    SBCPUPeachDockDropSetLayoutDepth(self, depth + 1);
    @try { SBCPUPeachDockOriginalNativeCreateAtIndex(self, cmd, icon, index); }
    @finally { SBCPUPeachDockDropSetLayoutDepth(self, depth); }
}
static void SBCPUPeachDockInstallDropMapping(Class dockClass) {
    SEL origin = @selector(originForIconAtCoordinate:metrics:options:);
    SEL column = @selector(columnAtPoint:metrics:fractionOfDistanceThroughColumn:);
    SEL layout = @selector(layoutIconsNow);
    SEL coreLayout = @selector(layoutIconsIfNeededUsingAnimator:options:);
    SEL center = @selector(centerForIconCoordinate:metrics:);
    const char *originArgs[] = { @encode(SBCPUPeachDockIconCoordinate), "@", @encode(NSUInteger) };
    const char *columnArgs[] = { @encode(CGPoint), "@", "^d" };
    const char *layoutArgs[] = { "@", @encode(NSUInteger) };
    const char *centerArgs[] = { @encode(SBCPUPeachDockIconCoordinate), "@" };
    BOOL ready = SBCPUPeachDockDropMethodMatches(dockClass, origin, @encode(CGPoint), originArgs, 3) &&
        SBCPUPeachDockDropMethodMatches(dockClass, column, @encode(NSUInteger), columnArgs, 3) &&
        SBCPUPeachDockDropMethodMatches(dockClass, layout, "v", NULL, 0) &&
        SBCPUPeachDockDropMethodMatches(dockClass, coreLayout, "v", layoutArgs, 2) &&
        SBCPUPeachDockDropMethodMatches(dockClass, center, @encode(CGPoint), centerArgs, 2);
    if (ready) {
        MSHookMessageEx(dockClass, origin, (IMP)SBCPUPeachDockHookNativeOrigin, (IMP *)&SBCPUPeachDockOriginalNativeOrigin);
        MSHookMessageEx(dockClass, column, (IMP)SBCPUPeachDockHookNativeColumn, (IMP *)&SBCPUPeachDockOriginalNativeColumn);
        MSHookMessageEx(dockClass, layout, (IMP)SBCPUPeachDockHookNativeLayoutNow, (IMP *)&SBCPUPeachDockOriginalNativeLayoutNow);
        MSHookMessageEx(dockClass, coreLayout, (IMP)SBCPUPeachDockHookNativeLayoutIcons, (IMP *)&SBCPUPeachDockOriginalNativeLayoutIcons);
        const char *createArgs[] = { "@" };
        const char *indexedArgs[] = { "@", @encode(NSUInteger) };
        SEL create = @selector(layoutAndCreateIcon:), indexed = @selector(layoutAndCreateIcon:atIndex:);
        if (SBCPUPeachDockDropMethodMatches(dockClass, create, "v", createArgs, 1))
            MSHookMessageEx(dockClass, create, (IMP)SBCPUPeachDockHookNativeCreate, (IMP *)&SBCPUPeachDockOriginalNativeCreate);
        if (SBCPUPeachDockDropMethodMatches(dockClass, indexed, "v", indexedArgs, 2))
            MSHookMessageEx(dockClass, indexed, (IMP)SBCPUPeachDockHookNativeCreateAtIndex, (IMP *)&SBCPUPeachDockOriginalNativeCreateAtIndex);
    }
}
