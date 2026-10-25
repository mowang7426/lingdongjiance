/*
 * Infinidock 16 Revival
 *
 * The original Infinidock implementation is:
 * Copyright (c) 2010-2014, Xuzz Productions, LLC
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED.
 */

// Plain Objective-C counterpart of Tweak.xm. No Logos/Theos preprocessing.
#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>
#import "SBCPUPeachDockPrivate.h"
#import "SBCPUPeachDockEdgeTransition.h"
#import "SBCPUPeachDockDockInteractionState.h"

extern void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);
#import "SBCPUPeachDockConfig.h"

@interface SBCPUPeachDockWeakOwner : NSObject
@property (nonatomic, weak) SBDockIconListView *list;
@end
@implementation SBCPUPeachDockWeakOwner
@end

static const NSUInteger SBCPUPeachDockMaximumDockIcons = 100;
static const NSUInteger SBCPUPeachDockDefaultIconsPerPage = 4;
#import "SBCPUPeachDockCapacity.h"
// The viewport, not a single device's 89 pt measurement, defines slot pitch.
static CGFloat SBCPUPeachDockIconPitch(SBDockIconListView *list) {
    return SBCPUPeachDockPitch(CGRectGetWidth(list.bounds));
}

static void *SBCPUPeachDockScrollViewKey = &SBCPUPeachDockScrollViewKey;
static void *SBCPUPeachDockClipViewKey = &SBCPUPeachDockClipViewKey;
static void *SBCPUPeachDockContentViewKey = &SBCPUPeachDockContentViewKey;
static void *SBCPUPeachDockAnchorYKey = &SBCPUPeachDockAnchorYKey;
static void *SBCPUPeachDockLayoutPendingKey = &SBCPUPeachDockLayoutPendingKey;
static void *SBCPUPeachDockOwnerListKey = &SBCPUPeachDockOwnerListKey;
static void *SBCPUPeachDockSpringApproachKey = &SBCPUPeachDockSpringApproachKey;
static void *SBCPUPeachDockSpringTargetKey = &SBCPUPeachDockSpringTargetKey;
static void *SBCPUPeachDockSpringTransitionKey = &SBCPUPeachDockSpringTransitionKey;
static void *SBCPUPeachDockSpringTokenKey = &SBCPUPeachDockSpringTokenKey;

static UIScrollView *SBCPUPeachDockScrollView(SBDockIconListView *listView);
static NSArray<SBIconView *> *SBCPUPeachDockSortedIconViews(SBDockIconListView *listView);
static UIView *SBCPUPeachDockDockBackgroundView(SBDockIconListView *listView);

static BOOL SBCPUPeachDockTweakEnabled(void) {
    return SBCPUPeachDockRequested();
}

static BOOL SBCPUPeachDockPagingEnabled(void) {
    return SBCPUPeachDockPaging();
}

static BOOL SBCPUPeachDockIsIconView(id object) {
    Class iconViewClass = objc_getClass("SBIconView");
    return iconViewClass != Nil && [object isKindOfClass:iconViewClass];
}

static UIScrollView *SBCPUPeachDockScrollView(SBDockIconListView *listView) {
    return objc_getAssociatedObject(listView, SBCPUPeachDockScrollViewKey);
}

static UIView *SBCPUPeachDockClipView(SBDockIconListView *listView) {
    return objc_getAssociatedObject(listView, SBCPUPeachDockClipViewKey);
}

static UIView *SBCPUPeachDockContentView(SBDockIconListView *listView) {
    return objc_getAssociatedObject(listView, SBCPUPeachDockContentViewKey);
}

// The module owns its association. Do not create a second association/cache here.
// Reject callbacks from another scroller, and never depend on a private class symbol.
static SBCPUPeachDockEdgeTransition *SBCPUPeachDockTransitionForList(id candidate) {
    Class dockClass = objc_getClass("SBDockIconListView");
    Class transitionClass = objc_getClass("SBCPUPeachDockEdgeTransition");
    if (candidate == nil || dockClass == Nil || transitionClass == Nil ||
        ![candidate isKindOfClass:dockClass] ||
        ![transitionClass respondsToSelector:
            @selector(transitionForListView:scrollView:contentView:clipView:)]) {
        return nil;
    }
    SBDockIconListView *listView = candidate;
    UIScrollView *scrollView = SBCPUPeachDockScrollView(listView);
    UIView *contentView = SBCPUPeachDockContentView(listView);
    UIView *clipView = SBCPUPeachDockClipView(listView);
    if (scrollView == nil || contentView == nil || clipView == nil) return nil;
    SBCPUPeachDockEdgeTransition *transition = [(id)transitionClass transitionForListView:listView
                                         scrollView:scrollView
                                        contentView:contentView
                                           clipView:clipView];
    // Feed the same Dock policy to the suppression API; the renderer also probes
    // the local getter at render time so display-link/async work cannot use stale flags.
    [transition setIconEditing:SBCPUPeachDockDockInteractionActive(listView)];
    return transition;
}

static SBCPUPeachDockEdgeTransition *SBCPUPeachDockTransitionForScrollView(
    SBDockIconListView *listView, UIScrollView *scrollView
) {
    return scrollView == SBCPUPeachDockScrollView(listView)
        ? SBCPUPeachDockTransitionForList(listView) : nil;
}

static SBDockView *SBCPUPeachDockDockViewForList(SBDockIconListView *listView) {
    Class dockClass = objc_getClass("SBDockView");
    for (UIView *ancestor = listView.superview;
         ancestor != nil;
         ancestor = ancestor.superview) {
        if (dockClass != Nil && [ancestor isKindOfClass:dockClass]) {
            return (SBDockView *)ancestor;
        }
    }
    return nil;
}

static UIView *SBCPUPeachDockDockBackgroundView(SBDockIconListView *listView) {
    // Hidden stock material still supplies the authoritative frame/corner radius
    // when LiquidAss inserts its LGLiveBackdropView sibling.
    SBDockView *dockView = SBCPUPeachDockDockViewForList(listView);
    UIView *backgroundView = dockView.backgroundView;
    if ([backgroundView isKindOfClass:UIView.class] &&
        CGRectGetWidth(backgroundView.bounds) > 0.0 &&
        CGRectGetHeight(backgroundView.bounds) > 0.0) {
        return backgroundView;
    }
    return nil;
}

static NSArray<SBIconView *> *SBCPUPeachDockSortedIconViews(SBDockIconListView *listView) {
    UIView *contentView = SBCPUPeachDockContentView(listView);
    if (contentView == nil) return @[];
    NSMutableArray<SBIconView *> *iconViews = [NSMutableArray array];
    for (UIView *view in contentView.subviews) {
        if (SBCPUPeachDockIsIconView(view)) [iconViews addObject:(SBIconView *)view];
    }
    NSArray *visibleIcons = nil;
    if ([listView respondsToSelector:@selector(visibleIcons)]) {
        visibleIcons = listView.visibleIcons;
    }
    [iconViews sortUsingComparator:^NSComparisonResult(SBIconView *left, SBIconView *right) {
        if (visibleIcons != nil &&
            [left respondsToSelector:@selector(icon)] &&
            [right respondsToSelector:@selector(icon)]) {
            NSUInteger leftIndex = [visibleIcons indexOfObjectIdenticalTo:left.icon];
            NSUInteger rightIndex = [visibleIcons indexOfObjectIdenticalTo:right.icon];
            if (leftIndex != NSNotFound && rightIndex != NSNotFound && leftIndex != rightIndex) {
                return leftIndex < rightIndex ? NSOrderedAscending : NSOrderedDescending;
            }
        }
        if (CGRectGetMinX(left.frame) == CGRectGetMinX(right.frame)) return NSOrderedSame;
        return CGRectGetMinX(left.frame) < CGRectGetMinX(right.frame)
            ? NSOrderedAscending : NSOrderedDescending;
    }];
    return iconViews;
}

static void SBCPUPeachDockCaptureAnchorY(SBDockIconListView *listView, UIView *iconView) {
    if (objc_getAssociatedObject(listView, SBCPUPeachDockAnchorYKey) != nil) return;
    CGFloat centerY = CGRectGetMidY(iconView.frame);
    if (isfinite(centerY) && centerY > 0.0) {
        objc_setAssociatedObject(listView, SBCPUPeachDockAnchorYKey, @(centerY),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void SBCPUPeachDockMoveExistingIconsIntoScrollView(SBDockIconListView *listView) {
    UIView *contentView = SBCPUPeachDockContentView(listView);
    if (contentView == nil) return;
    for (UIView *view in [listView.subviews copy]) {
        if (!SBCPUPeachDockIsIconView(view)) continue;
        SBCPUPeachDockCaptureAnchorY(listView, view);
        [contentView addSubview:view];
    }
}

static void SBCPUPeachDockInstallScrollViewIfNeeded(SBDockIconListView *listView) {
    if (SBCPUPeachDockScrollView(listView) != nil || listView.bounds.size.width <= 0.0) return;
    UIView *clipView = [[UIView alloc] initWithFrame:listView.bounds];
    clipView.backgroundColor = UIColor.clearColor;
    clipView.clipsToBounds = YES;
    clipView.userInteractionEnabled = YES;
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:listView.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrollView.backgroundColor = UIColor.clearColor;
    scrollView.clipsToBounds = YES;
    scrollView.pagingEnabled = SBCPUPeachDockPagingEnabled();
    scrollView.decelerationRate = scrollView.pagingEnabled
        ? UIScrollViewDecelerationRateFast : UIScrollViewDecelerationRateNormal;
    scrollView.bounces = YES;
    scrollView.alwaysBounceHorizontal = YES;
    scrollView.alwaysBounceVertical = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.directionalLockEnabled = YES;
    scrollView.delegate = (id<UIScrollViewDelegate>)listView;
    UIView *contentView = [[UIView alloc] initWithFrame:scrollView.bounds];
    contentView.backgroundColor = UIColor.clearColor;
    SBCPUPeachDockWeakOwner *owner = [SBCPUPeachDockWeakOwner new];
    owner.list = listView;
    objc_setAssociatedObject(contentView, SBCPUPeachDockOwnerListKey, owner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [scrollView addSubview:contentView];
    [clipView addSubview:scrollView];
    objc_setAssociatedObject(listView, SBCPUPeachDockClipViewKey, clipView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(listView, SBCPUPeachDockScrollViewKey, scrollView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(listView, SBCPUPeachDockContentViewKey, contentView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [listView insertSubview:clipView atIndex:0];
    SBCPUPeachDockMoveExistingIconsIntoScrollView(listView);
}

static SBDockIconListView *SBCPUPeachDockOwningListView(SBIconView *iconView) {
    UIView *superview = iconView.superview;
    SBCPUPeachDockWeakOwner *box = superview != nil ? objc_getAssociatedObject(superview, SBCPUPeachDockOwnerListKey) : nil;
    id owner = box.list;
    Class dockClass = objc_getClass("SBDockIconListView");
    if (owner != nil && dockClass != Nil && [owner isKindOfClass:dockClass]) {
        return (SBDockIconListView *)owner;
    }
    return nil;
}

static NSUInteger SBCPUPeachDockIndexForIconView(SBDockIconListView *listView, SBIconView *iconView) {
    NSArray *visibleIcons = listView.visibleIcons;
    if (visibleIcons != nil && [iconView respondsToSelector:@selector(icon)]) {
        NSUInteger modelIndex = [visibleIcons indexOfObjectIdenticalTo:iconView.icon];
        if (modelIndex != NSNotFound) return modelIndex;
    }
    UIView *contentView = SBCPUPeachDockContentView(listView);
    NSUInteger fallbackIndex = 0;
    for (UIView *view in contentView.subviews) {
        if (!SBCPUPeachDockIsIconView(view)) continue;
        if (view == iconView) return fallbackIndex;
        fallbackIndex++;
    }
    return NSNotFound;
}

static void SBCPUPeachDockUpdateScrollExtent(SBDockIconListView *listView, NSUInteger minimumIconCount) {
    UIScrollView *scrollView = SBCPUPeachDockScrollView(listView);
    UIView *contentView = SBCPUPeachDockContentView(listView);
    if (scrollView == nil || contentView == nil) return;
    CGFloat pageWidth = CGRectGetWidth(scrollView.bounds);
    CGFloat pageHeight = CGRectGetHeight(scrollView.bounds);
    if (!isfinite(pageWidth) || !isfinite(pageHeight) || pageWidth <= 0.0 || pageHeight <= 0.0) return;
    NSUInteger iconCount = MAX(listView.visibleIcons.count, minimumIconCount);
    NSUInteger pageCount = MAX((NSUInteger)1,
        (iconCount + SBCPUPeachDockDefaultIconsPerPage - 1) / SBCPUPeachDockDefaultIconsPerPage);
    CGSize contentSize = CGSizeMake(pageWidth * pageCount, pageHeight);
    if (CGSizeEqualToSize(scrollView.contentSize, contentSize) &&
        CGSizeEqualToSize(contentView.frame.size, contentSize)) return;
    scrollView.contentSize = contentSize;
    contentView.frame = (CGRect){ CGPointZero, contentSize };
}

static BOOL SBCPUPeachDockCorrectedCenterForIconView(
    SBIconView *iconView, CGPoint *correctedCenter, NSUInteger *correctedIndex
) {
    SBDockIconListView *listView = SBCPUPeachDockOwningListView(iconView);
    UIScrollView *scrollView = listView != nil ? SBCPUPeachDockScrollView(listView) : nil;
    if (listView == nil || scrollView == nil || SBCPUPeachDockDockInteractionActive(listView)) return NO;
    NSUInteger iconIndex = SBCPUPeachDockIndexForIconView(listView, iconView);
    CGFloat pageWidth = CGRectGetWidth(scrollView.bounds);
    CGFloat pageHeight = CGRectGetHeight(scrollView.bounds);
    if (iconIndex == NSNotFound || !isfinite(pageWidth) || !isfinite(pageHeight) ||
        pageWidth <= 0.0 || pageHeight <= 0.0) return NO;
    SBCPUPeachDockUpdateScrollExtent(listView, iconIndex + 1);
    // Keep SpringBoard's incoming vertical center; extend its four-icon pitch by pages.
    CGFloat iconPitch = SBCPUPeachDockIconPitch(listView);
    CGFloat groupWidth = iconPitch * (SBCPUPeachDockDefaultIconsPerPage - 1);
    CGFloat firstCenterX = (pageWidth - groupWidth) / 2.0;
    *correctedCenter = CGPointMake(
        pageWidth * floor((CGFloat)iconIndex / SBCPUPeachDockDefaultIconsPerPage) + firstCenterX +
        iconPitch * (CGFloat)(iconIndex % SBCPUPeachDockDefaultIconsPerPage), correctedCenter->y);
    if (correctedIndex != NULL) *correctedIndex = iconIndex;
    return YES;
}

static void SBCPUPeachDockLayoutDock(SBDockIconListView *listView) {
    UIScrollView *scrollView = SBCPUPeachDockScrollView(listView);
    UIView *contentView = SBCPUPeachDockContentView(listView);
    UIView *clipView = SBCPUPeachDockClipView(listView);
    if (scrollView == nil || contentView == nil || clipView == nil) return;
    // Keep the native full-width icon coordinate space inside the real Dock viewport.
    CGRect clipFrame = listView.bounds;
    UIView *dockBackgroundView = SBCPUPeachDockDockBackgroundView(listView);
    if (dockBackgroundView != nil) {
        CGRect backgroundFrame = [listView convertRect:dockBackgroundView.bounds fromView:dockBackgroundView];
        if (isfinite(CGRectGetMinX(backgroundFrame)) && isfinite(CGRectGetMinY(backgroundFrame)) &&
            CGRectGetWidth(backgroundFrame) > 0.0 && CGRectGetHeight(backgroundFrame) > 0.0) {
            clipFrame = backgroundFrame;
        }
    }
    clipView.frame = clipFrame;
    clipView.clipsToBounds = YES;
    CGFloat cornerRadius = dockBackgroundView != nil ? dockBackgroundView.layer.cornerRadius : 0.0;
    clipView.layer.cornerRadius = cornerRadius;
    clipView.layer.masksToBounds = YES;
    scrollView.frame = CGRectMake(-CGRectGetMinX(clipFrame), -CGRectGetMinY(clipFrame),
        CGRectGetWidth(listView.bounds), CGRectGetHeight(listView.bounds));
    listView.clipsToBounds = NO;
    scrollView.clipsToBounds = YES;
    scrollView.layer.cornerRadius = 0.0;
    scrollView.layer.masksToBounds = YES;
    NSArray<SBIconView *> *iconViews = SBCPUPeachDockSortedIconViews(listView);
    CGFloat pageWidth = CGRectGetWidth(scrollView.bounds);
    CGFloat pageHeight = CGRectGetHeight(scrollView.bounds);
    if (pageWidth <= 0.0 || pageHeight <= 0.0) return;
    CGFloat slotWidth = pageWidth / SBCPUPeachDockDefaultIconsPerPage;
    NSUInteger iconCount = MAX(iconViews.count, listView.visibleIcons.count);
    SBCPUPeachDockUpdateScrollExtent(listView, iconCount);
    // SpringBoard's hooked origin calculation remains the source of truth.
    (void)slotWidth;
    (void)iconViews;
    [SBCPUPeachDockTransitionForList(listView) layout];
}

static void SBCPUPeachDockScheduleDeferredLayout(SBDockIconListView *listView) {
    if (objc_getAssociatedObject(listView, SBCPUPeachDockLayoutPendingKey) != nil) return;
    objc_setAssociatedObject(listView, SBCPUPeachDockLayoutPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak SBDockIconListView *weakListView = listView;
    dispatch_async(dispatch_get_main_queue(), ^{
        SBDockIconListView *strongListView = weakListView;
        if (strongListView == nil) return;
        objc_setAssociatedObject(strongListView, SBCPUPeachDockLayoutPendingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SBCPUPeachDockMoveExistingIconsIntoScrollView(strongListView);
        SBCPUPeachDockLayoutDock(strongListView);
    });
}

// Balance only the animator owned by this tweak. stopAnimation:YES deliberately
// skips completions, so the cancelled generation must end its spring explicitly.
static void SBCPUPeachDockCancelSpringSettle(UIScrollView *scrollView) {
    UIViewPropertyAnimator *previous = objc_getAssociatedObject(scrollView, SBCPUPeachDockSpringApproachKey);
    if (previous == nil) return;
    SBCPUPeachDockEdgeTransition *transition = objc_getAssociatedObject(scrollView, SBCPUPeachDockSpringTransitionKey);
    CALayer *presentation = scrollView.layer.presentationLayer;
    CGPoint displayedOffset = presentation != nil ? presentation.bounds.origin : scrollView.contentOffset;
    BOOL wasActive = previous.state == UIViewAnimatingStateActive;
    // Invalidate ownership before stopping: even an unexpected old completion
    // cannot clear a replacement generation's flag or associated objects.
    objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringTokenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringApproachKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringTransitionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (wasActive) {
        [previous stopAnimation:YES];
        if (isfinite(displayedOffset.x) && isfinite(displayedOffset.y)) {
            // Hand a new pan/settle the visible position, not the already-advanced
            // model endpoint. This does not change the paging/deceleration policy.
            scrollView.contentOffset = displayedOffset;
        }
    }
    [transition endSpring];
}

// Preserve the measured 0.42 s / 0.72 spring and existing paging takeover.
static void SBCPUPeachDockBeginSpringSettle(UIScrollView *scrollView, CGPoint targetOffset, CGPoint velocity) {
    if (!SBCPUPeachDockPagingEnabled() || !SBCPUPeachDockSpring() || UIAccessibilityIsReduceMotionEnabled() || SBCPUPeachDockDockInteractionActive(scrollView.delegate)) return;
    SBCPUPeachDockCancelSpringSettle(scrollView);
    objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringTargetKey, [NSValue valueWithCGPoint:targetOffset],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGVector initialVelocity = CGVectorMake(velocity.x / 400.0, 0.0);
    UISpringTimingParameters *parameters = [[UISpringTimingParameters alloc]
        initWithDampingRatio:0.72 initialVelocity:initialVelocity];
    UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc]
        initWithDuration:0.42 timingParameters:parameters];
    SBCPUPeachDockEdgeTransition *transition = SBCPUPeachDockTransitionForList(scrollView.delegate);
    NSObject *token = [NSObject new];
    [animator addAnimations:^{ scrollView.contentOffset = targetOffset; }];
    [animator addCompletion:^(UIViewAnimatingPosition finalPosition) {
        (void)finalPosition;
        if (objc_getAssociatedObject(scrollView, SBCPUPeachDockSpringTokenKey) != token) return;
        objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringTokenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringApproachKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringTransitionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [transition endSpring];
    }];
    objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringApproachKey, animator, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(scrollView, SBCPUPeachDockSpringTransitionKey, transition, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [transition beginSpring];
    [animator startAnimation];
}

#pragma mark - SBDockIconListView hook functions

static unsigned long long (*SBCPUPeachDockOriginalMaxIcons)(id, SEL);
static unsigned long long SBCPUPeachDockHookMaxIcons(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return SBCPUPeachDockMaximumDockIcons;
}

static CGPoint (*SBCPUPeachDockOriginalOrigin)(SBDockIconListView *, SEL, SBCPUPeachDockIconCoordinate, unsigned long long);
static CGPoint SBCPUPeachDockHookOrigin(SBDockIconListView *self, SEL _cmd,
                             SBCPUPeachDockIconCoordinate coordinate, unsigned long long numberOfIcons) {
    CGPoint originalOrigin = SBCPUPeachDockOriginalOrigin(self, _cmd, coordinate, numberOfIcons);
    if (coordinate.col < 1) return originalOrigin;
    CGFloat pageWidth = CGRectGetWidth(self.bounds);
    if (!isfinite(pageWidth) || pageWidth <= 0.0) return originalOrigin;
    CGFloat iconPitch = SBCPUPeachDockIconPitch(self);
    CGFloat groupWidth = iconPitch * (SBCPUPeachDockDefaultIconsPerPage - 1);
    CGFloat firstCenterX = (pageWidth - groupWidth) / 2.0;
    CGFloat iconWidth = 0.0;
    NSArray<SBIconView *> *iconViews = SBCPUPeachDockSortedIconViews(self);
    if (iconViews.count > 0) iconWidth = CGRectGetWidth(iconViews.firstObject.bounds);
    // This legacy selector is absent on stock 16.2; never guess another private
    // getter or hard-code a size when an alternate runtime supplies this path.
    if (!isfinite(iconWidth) || iconWidth <= 0.0) return originalOrigin;
    NSUInteger zeroBasedIndex = (NSUInteger)(coordinate.col - 1);
    NSUInteger page = zeroBasedIndex / SBCPUPeachDockDefaultIconsPerPage;
    NSUInteger slot = zeroBasedIndex % SBCPUPeachDockDefaultIconsPerPage;
    CGPoint adjustedOrigin = originalOrigin;
    adjustedOrigin.x = pageWidth * page + firstCenterX + iconPitch * (CGFloat)slot - iconWidth / 2.0;
    return adjustedOrigin;
}

#import "SBCPUPeachDockDockDropMapping.h"
#import "SBCPUPeachDockDockDropPreviewMapping.h"

static void (*SBCPUPeachDockOriginalListDidMove)(SBDockIconListView *, SEL);
static void SBCPUPeachDockHookListDidMove(SBDockIconListView *self, SEL _cmd) {
    if (SBCPUPeachDockOriginalListDidMove) SBCPUPeachDockOriginalListDidMove(self, _cmd);
    SBCPUPeachDockInstallScrollViewIfNeeded(self);
    SBCPUPeachDockMoveExistingIconsIntoScrollView(self);
    SBCPUPeachDockLayoutDock(self);
    SBCPUPeachDockScheduleDeferredLayout(self);
}

static void (*SBCPUPeachDockOriginalListAddSubview)(SBDockIconListView *, SEL, UIView *);
static void SBCPUPeachDockHookListAddSubview(SBDockIconListView *self, SEL _cmd, UIView *view) {
    UIView *contentView = SBCPUPeachDockContentView(self);
    if (contentView != nil && SBCPUPeachDockIsIconView(view)) {
        SBCPUPeachDockCaptureAnchorY(self, view);
        [contentView addSubview:view];
        return;
    }
    if (SBCPUPeachDockOriginalListAddSubview) SBCPUPeachDockOriginalListAddSubview(self, _cmd, view);
}

static void (*SBCPUPeachDockOriginalListLayout)(SBDockIconListView *, SEL);
static void SBCPUPeachDockHookListLayout(SBDockIconListView *self, SEL _cmd) {
    SBCPUPeachDockBindModel(self, SBCPUPeachDockReadModel(self));
    SBCPUPeachDockInstallScrollViewIfNeeded(self);
    if (SBCPUPeachDockDockInteractionActive(self)) {
        SBCPUPeachDockCancelSpringSettle(SBCPUPeachDockScrollView(self));
        [SBCPUPeachDockTransitionForList(self) layout];
    }
    NSUInteger layoutDepth = SBCPUPeachDockDropLayoutDepth(self);
    SBCPUPeachDockDropSetLayoutDepth(self, layoutDepth + 1);
    @try { if (SBCPUPeachDockOriginalListLayout) SBCPUPeachDockOriginalListLayout(self, _cmd); }
    @finally { SBCPUPeachDockDropSetLayoutDepth(self, layoutDepth); }
    SBCPUPeachDockMoveExistingIconsIntoScrollView(self);
    SBCPUPeachDockLayoutDock(self);
    SBCPUPeachDockScheduleDeferredLayout(self);
}

static void (*SBCPUPeachDockOriginalWillEndDragging)(SBDockIconListView *, SEL, UIScrollView *, CGPoint, CGPoint *);
static void SBCPUPeachDockHookWillEndDragging(SBDockIconListView *self, SEL _cmd,
                                   UIScrollView *scrollView, CGPoint velocity, CGPoint *targetContentOffset) {
    if (scrollView != SBCPUPeachDockScrollView(self) || SBCPUPeachDockDockInteractionActive(self) || !SBCPUPeachDockPagingEnabled()) {
        if (scrollView == SBCPUPeachDockScrollView(self) && SBCPUPeachDockDockInteractionActive(self)) {
            SBCPUPeachDockCancelSpringSettle(scrollView);
            [SBCPUPeachDockTransitionForScrollView(self, scrollView) layout];
        }
        if (SBCPUPeachDockOriginalWillEndDragging) SBCPUPeachDockOriginalWillEndDragging(self, _cmd, scrollView, velocity, targetContentOffset);
        return;
    }
    CGFloat pageWidth = CGRectGetWidth(scrollView.bounds);
    if (pageWidth > 0.0 && targetContentOffset != NULL) {
        NSInteger targetPage = (NSInteger)lround(targetContentOffset->x / pageWidth);
        CGFloat maxOffset = scrollView.contentSize.width - pageWidth;
        NSInteger maxPage = maxOffset > 0.0 ? (NSInteger)lround(maxOffset / pageWidth) : 0;
        if (targetPage < 0) targetPage = 0;
        if (targetPage > maxPage) targetPage = maxPage;
        CGPoint target = CGPointMake(targetPage * pageWidth, 0.0);
        *targetContentOffset = target;
        if (SBCPUPeachDockOriginalWillEndDragging) SBCPUPeachDockOriginalWillEndDragging(self, _cmd, scrollView, velocity, targetContentOffset);
        SBCPUPeachDockBeginSpringSettle(scrollView, target, velocity);
        return;
    }
    if (SBCPUPeachDockOriginalWillEndDragging) SBCPUPeachDockOriginalWillEndDragging(self, _cmd, scrollView, velocity, targetContentOffset);
}

static void (*SBCPUPeachDockOriginalWillBeginDragging)(SBDockIconListView *, SEL, UIScrollView *);
static void SBCPUPeachDockHookWillBeginDragging(SBDockIconListView *self, SEL _cmd, UIScrollView *scrollView) {
    if (SBCPUPeachDockOriginalWillBeginDragging) SBCPUPeachDockOriginalWillBeginDragging(self, _cmd, scrollView);
    SBCPUPeachDockEdgeTransition *transition = SBCPUPeachDockTransitionForScrollView(self, scrollView);
    [transition beginInteraction];
    if (scrollView == SBCPUPeachDockScrollView(self)) SBCPUPeachDockCancelSpringSettle(scrollView);
}

static void (*SBCPUPeachDockOriginalDidScroll)(SBDockIconListView *, SEL, UIScrollView *);
static void SBCPUPeachDockHookDidScroll(SBDockIconListView *self, SEL _cmd, UIScrollView *scrollView) {
    if (SBCPUPeachDockOriginalDidScroll) SBCPUPeachDockOriginalDidScroll(self, _cmd, scrollView);
    if (scrollView == SBCPUPeachDockScrollView(self) && SBCPUPeachDockDockInteractionActive(self)) SBCPUPeachDockCancelSpringSettle(scrollView);
    [SBCPUPeachDockTransitionForScrollView(self, scrollView) scrollDidChange];
}

static void (*SBCPUPeachDockOriginalDidEndDragging)(SBDockIconListView *, SEL, UIScrollView *, BOOL);
static void SBCPUPeachDockHookDidEndDragging(SBDockIconListView *self, SEL _cmd,
                                  UIScrollView *scrollView, BOOL decelerate) {
    if (SBCPUPeachDockOriginalDidEndDragging) SBCPUPeachDockOriginalDidEndDragging(self, _cmd, scrollView, decelerate);
    if (!decelerate) [SBCPUPeachDockTransitionForScrollView(self, scrollView) endInteraction];
}

static void (*SBCPUPeachDockOriginalDidEndDecelerating)(SBDockIconListView *, SEL, UIScrollView *);
static void SBCPUPeachDockHookDidEndDecelerating(SBDockIconListView *self, SEL _cmd, UIScrollView *scrollView) {
    if (SBCPUPeachDockOriginalDidEndDecelerating) SBCPUPeachDockOriginalDidEndDecelerating(self, _cmd, scrollView);
    [SBCPUPeachDockTransitionForScrollView(self, scrollView) endInteraction];
}

static void (*SBCPUPeachDockOriginalDidEndScrollingAnimation)(SBDockIconListView *, SEL, UIScrollView *);
static void SBCPUPeachDockHookDidEndScrollingAnimation(SBDockIconListView *self, SEL _cmd, UIScrollView *scrollView) {
    if (SBCPUPeachDockOriginalDidEndScrollingAnimation) SBCPUPeachDockOriginalDidEndScrollingAnimation(self, _cmd, scrollView);
    [SBCPUPeachDockTransitionForScrollView(self, scrollView) endInteraction];
}

#pragma mark - Other original hooks

static void (*SBCPUPeachDockOriginalDockLayout)(SBDockView *, SEL);
static void SBCPUPeachDockHookDockLayout(SBDockView *self, SEL _cmd) {
    if (SBCPUPeachDockOriginalDockLayout) SBCPUPeachDockOriginalDockLayout(self, _cmd);
    // Do not mask LiquidAss's live-backdrop sibling of the icon list.
    self.layer.mask = nil;
}

static void (*SBCPUPeachDockOriginalDockDidMove)(SBDockView *, SEL);
static void SBCPUPeachDockHookDockDidMove(SBDockView *self, SEL _cmd) {
    if (SBCPUPeachDockOriginalDockDidMove) SBCPUPeachDockOriginalDockDidMove(self, _cmd);
    self.layer.mask = nil;
}

static void (*SBCPUPeachDockOriginalSetCenter)(SBIconView *, SEL, CGPoint);
static void SBCPUPeachDockHookSetCenter(SBIconView *self, SEL _cmd, CGPoint center) {
    CGPoint correctedCenter = center;
    (void)SBCPUPeachDockCorrectedCenterForIconView(self, &correctedCenter, NULL);
    if (SBCPUPeachDockOriginalSetCenter) SBCPUPeachDockOriginalSetCenter(self, _cmd, correctedCenter);
}

static void (*SBCPUPeachDockOriginalSetFrame)(SBIconView *, SEL, CGRect);
static void SBCPUPeachDockHookSetFrame(SBIconView *self, SEL _cmd, CGRect frame) {
    CGPoint correctedCenter = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    if (SBCPUPeachDockCorrectedCenterForIconView(self, &correctedCenter, NULL)) {
        frame.origin.x = correctedCenter.x - CGRectGetWidth(frame) / 2.0;
        frame.origin.y = correctedCenter.y - CGRectGetHeight(frame) / 2.0;
    }
    if (SBCPUPeachDockOriginalSetFrame) SBCPUPeachDockOriginalSetFrame(self, _cmd, frame);
}

// An init-family IMP consumes its receiver and returns +1. C functions have no
// method-family inference, so both the original type and replacement spell it out.
typedef id (*SBCPUPeachDockModelInitIMP)(id self __attribute__((ns_consumed)), SEL _cmd,
    id folder, unsigned long long maxIconCount) __attribute__((ns_returns_retained));
static SBCPUPeachDockModelInitIMP SBCPUPeachDockOriginalModelInit;
static id SBCPUPeachDockHookModelInit(id self __attribute__((ns_consumed)), SEL _cmd,
    id folder, unsigned long long maxIconCount) __attribute__((ns_returns_retained));
static id SBCPUPeachDockHookModelInit(id self __attribute__((ns_consumed)), SEL _cmd,
                           id folder, unsigned long long maxIconCount) {
    // Init remains transparent: ownership is established from the actual Dock
    // view's model getter/setter, never from a four-slot count or folder class.
    return SBCPUPeachDockOriginalModelInit(self, _cmd, folder, maxIconCount);
}

static id (*SBCPUPeachDockOriginalProviderLayout)(SBHDefaultIconListLayoutProvider *, SEL, id);
static id SBCPUPeachDockHookProviderLayout(SBHDefaultIconListLayoutProvider *self, SEL _cmd, id iconLocation) {
    id layout = SBCPUPeachDockOriginalProviderLayout(self, _cmd, iconLocation);
    if (![iconLocation isKindOfClass:NSString.class] ||
        ![(NSString *)iconLocation isEqualToString:@"SBIconLocationDock"]) return layout;
    if ([layout respondsToSelector:@selector(layoutConfiguration)]) {
        SBIconListGridLayoutConfiguration *configuration = [(SBIconListGridLayout *)layout layoutConfiguration];
        if ([configuration respondsToSelector:@selector(setNumberOfPortraitRows:)]) {
            configuration.numberOfPortraitRows = 1;
            configuration.numberOfLandscapeRows = 1;
            configuration.numberOfPortraitColumns = SBCPUPeachDockMaximumDockIcons;
            configuration.numberOfLandscapeColumns = SBCPUPeachDockMaximumDockIcons;
        }
    }
    return layout;
}

// Existing and inherited methods use Substrate's chaining API. Only genuinely
// absent delegate selectors are added; never replace/exchange an existing IMP.
static void SBCPUPeachDockInstallHook(Class cls, SEL selector, IMP replacement, IMP *original, const char *types) {
    if (cls == Nil) return;
    if (class_getInstanceMethod(cls, selector) != NULL) {
        MSHookMessageEx(cls, selector, replacement, original);
    } else if (types != NULL) {
        class_addMethod(cls, selector, replacement, types);
    }
}

#import "SBCPUPeachDockPreflight.h"

__attribute__((constructor)) static void SBCPUPeachDockInitialize(void) {
    @autoreleasepool {
        @try {
            if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
            SBCPUPeachDockLoadSnapshot();
            NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
            // No hook or class_addMethod occurs before the complete profile gate.
            // 16.2 archive comments alone are NOT a verified model/recovery ABI.
            if (!SBCPUPeachDockProfileApproved((int)version.majorVersion, (int)version.minorVersion) ||
                SBCPUPeachDockConflict()) return;
            Class dockClass = objc_getClass("SBDockIconListView");
            Class modelClass = objc_getClass("SBIconListModel");
            Class providerClass = objc_getClass("SBHDefaultIconListLayoutProvider");
            Class iconViewClass = objc_getClass("SBIconView");
            Class dockViewClass = objc_getClass("SBDockView");
            if (!SBCPUPeachDockTweakEnabled()) {
                return;
            }
            if (version.majorVersion >= 15 && version.majorVersion <= 16 &&
                dockClass != Nil && modelClass != Nil && iconViewClass != Nil && dockViewClass != Nil &&
                SBCPUPeachDockPreflight(dockClass, modelClass, providerClass, iconViewClass, dockViewClass)) {
                SBCPUPeachDockInstallCapacity(dockClass, modelClass);
                SBCPUPeachDockInstallHook(object_getClass(dockClass), @selector(maxIcons),
                    (IMP)SBCPUPeachDockHookMaxIcons, (IMP *)&SBCPUPeachDockOriginalMaxIcons, "Q@:");
                SBCPUPeachDockInstallHook(dockClass, @selector(originForIconAtCoordinate:numberOfIcons:),
                    (IMP)SBCPUPeachDockHookOrigin, (IMP *)&SBCPUPeachDockOriginalOrigin, NULL);
                SBCPUPeachDockInstallDropMapping(dockClass);
                SBCPUPeachDockInstallDropPreviewMapping();
                SBCPUPeachDockInstallHook(dockClass, @selector(didMoveToWindow),
                    (IMP)SBCPUPeachDockHookListDidMove, (IMP *)&SBCPUPeachDockOriginalListDidMove, NULL);
                SBCPUPeachDockInstallHook(dockClass, @selector(addSubview:),
                    (IMP)SBCPUPeachDockHookListAddSubview, (IMP *)&SBCPUPeachDockOriginalListAddSubview, NULL);
                SBCPUPeachDockInstallHook(dockClass, @selector(layoutSubviews),
                    (IMP)SBCPUPeachDockHookListLayout, (IMP *)&SBCPUPeachDockOriginalListLayout, NULL);
                SBCPUPeachDockInstallHook(dockClass, @selector(scrollViewWillEndDragging:withVelocity:targetContentOffset:),
                    (IMP)SBCPUPeachDockHookWillEndDragging, (IMP *)&SBCPUPeachDockOriginalWillEndDragging,
                    "v@:@{CGPoint=dd}^{CGPoint=dd}");
                SBCPUPeachDockInstallHook(dockClass, @selector(scrollViewWillBeginDragging:),
                    (IMP)SBCPUPeachDockHookWillBeginDragging, (IMP *)&SBCPUPeachDockOriginalWillBeginDragging, "v@:@");
                SBCPUPeachDockInstallHook(dockClass, @selector(scrollViewDidScroll:),
                    (IMP)SBCPUPeachDockHookDidScroll, (IMP *)&SBCPUPeachDockOriginalDidScroll, "v@:@");
                SBCPUPeachDockInstallHook(dockClass, @selector(scrollViewDidEndDragging:willDecelerate:),
                    (IMP)SBCPUPeachDockHookDidEndDragging, (IMP *)&SBCPUPeachDockOriginalDidEndDragging, "v@:@B");
                SBCPUPeachDockInstallHook(dockClass, @selector(scrollViewDidEndDecelerating:),
                    (IMP)SBCPUPeachDockHookDidEndDecelerating, (IMP *)&SBCPUPeachDockOriginalDidEndDecelerating, "v@:@");
                SBCPUPeachDockInstallHook(dockClass, @selector(scrollViewDidEndScrollingAnimation:),
                    (IMP)SBCPUPeachDockHookDidEndScrollingAnimation, (IMP *)&SBCPUPeachDockOriginalDidEndScrollingAnimation, "v@:@");
                SBCPUPeachDockInstallHook(dockViewClass, @selector(layoutSubviews),
                    (IMP)SBCPUPeachDockHookDockLayout, (IMP *)&SBCPUPeachDockOriginalDockLayout, NULL);
                SBCPUPeachDockInstallHook(dockViewClass, @selector(didMoveToWindow),
                    (IMP)SBCPUPeachDockHookDockDidMove, (IMP *)&SBCPUPeachDockOriginalDockDidMove, NULL);
                SBCPUPeachDockInstallHook(iconViewClass, @selector(setCenter:),
                    (IMP)SBCPUPeachDockHookSetCenter, (IMP *)&SBCPUPeachDockOriginalSetCenter, NULL);
                SBCPUPeachDockInstallHook(iconViewClass, @selector(setFrame:),
                    (IMP)SBCPUPeachDockHookSetFrame, (IMP *)&SBCPUPeachDockOriginalSetFrame, NULL);
                SBCPUPeachDockInstallHook(modelClass, @selector(initWithFolder:maxIconCount:),
                    (IMP)SBCPUPeachDockHookModelInit, (IMP *)&SBCPUPeachDockOriginalModelInit, NULL);
                if (providerClass != Nil) {
                    SBCPUPeachDockInstallHook(providerClass, @selector(layoutForIconLocation:),
                        (IMP)SBCPUPeachDockHookProviderLayout, (IMP *)&SBCPUPeachDockOriginalProviderLayout, NULL);
                }
            }
        } @catch (__unused NSException *exception) {
            // Preserve the existing constructor exception boundary without logging.
        }
    }
}
