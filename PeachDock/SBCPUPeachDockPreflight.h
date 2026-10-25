// Included after both drop adapters. Validate every dependent method before
// mutating any method table. This checks ABI, not Apple's persistence call graph.
static BOOL SBCPUPeachDockCheck(Class cls, const char *name, const char *types, BOOL optional) {
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return cls && optional;
    NSMethodSignature *expected = [NSMethodSignature signatureWithObjCTypes:types];
    NSMethodSignature *actual = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (!actual || actual.numberOfArguments != expected.numberOfArguments ||
        !SBCPUPeachDockDropTypeMatches(actual.methodReturnType, expected.methodReturnType)) return NO;
    for (NSUInteger i = 0; i < actual.numberOfArguments; ++i)
        if (!SBCPUPeachDockDropTypeMatches([actual getArgumentTypeAtIndex:i], [expected getArgumentTypeAtIndex:i])) return NO;
    return YES;
}
static BOOL SBCPUPeachDockPreflight(Class dock, Class model, Class provider, Class icon, Class view) {
    if (!SBCPUPeachDockCapacityReady(dock, model) || !SBCPUPeachDockRestoreReady() ||
        !SBCPUPeachDockDisableReady()) return NO;
    struct SBCPUPeachDockRequirement { Class cls; const char *selector; const char *types; BOOL optional; };
    const struct SBCPUPeachDockRequirement requirements[] = {
        {object_getClass(dock), "maxIcons", "Q@:", YES},
        {dock, "originForIconAtCoordinate:numberOfIcons:", "{CGPoint=dd}@:{Coordinate=qq}Q", YES},
        {dock, "originForIconAtCoordinate:metrics:options:", "{CGPoint=dd}@:{Coordinate=qq}@Q", NO},
        {dock, "centerForIconCoordinate:metrics:", "{CGPoint=dd}@:{Coordinate=qq}@", NO},
        {dock, "columnAtPoint:metrics:fractionOfDistanceThroughColumn:", "Q@:{CGPoint=dd}@^d", NO},
        {dock, "layoutIconsNow", "v@:", NO},
        {dock, "layoutIconsIfNeededUsingAnimator:options:", "v@:@Q", NO},
        {dock, "layoutAndCreateIcon:", "v@:@", NO},
        {dock, "layoutAndCreateIcon:atIndex:", "v@:@Q", NO},
        {dock, "isLayoutReversed", "B@:", NO},
        {dock, "visibleIcons", "@@:", NO},
        {dock, "iconLocation", "@@:", NO},
        {dock, "didMoveToWindow", "v@:", NO},
        {dock, "addSubview:", "v@:@", NO},
        {dock, "layoutSubviews", "v@:", NO},
        {dock, "scrollViewWillEndDragging:withVelocity:targetContentOffset:", "v@:@{CGPoint=dd}^{CGPoint=dd}", YES},
        {dock, "scrollViewWillBeginDragging:", "v@:@", YES},
        {dock, "scrollViewDidScroll:", "v@:@", YES},
        {dock, "scrollViewDidEndDragging:willDecelerate:", "v@:@B", YES},
        {dock, "scrollViewDidEndDecelerating:", "v@:@", YES},
        {dock, "scrollViewDidEndScrollingAnimation:", "v@:@", YES},
        {view, "layoutSubviews", "v@:", NO},
        {view, "didMoveToWindow", "v@:", NO},
        {view, "backgroundView", "@@:", NO},
        {view, "dockListView", "@@:", NO},
        {icon, "setCenter:", "v@:{CGPoint=dd}", NO},
        {icon, "setFrame:", "v@:{CGRect={CGPoint=dd}{CGSize=dd}}", NO},
        {icon, "icon", "@@:", NO},
        {provider, "layoutForIconLocation:", "@@:@", NO},
        {objc_getClass("SBIconListGridLayout"), "layoutConfiguration", "@@:", NO},
        {objc_getClass("SBIconListGridLayoutConfiguration"), "setNumberOfPortraitRows:", "v@:Q", NO},
        {objc_getClass("SBIconListGridLayoutConfiguration"), "setNumberOfLandscapeRows:", "v@:Q", NO},
        {objc_getClass("SBIconListGridLayoutConfiguration"), "setNumberOfPortraitColumns:", "v@:Q", NO},
        {objc_getClass("SBIconListGridLayoutConfiguration"), "setNumberOfLandscapeColumns:", "v@:Q", NO},
    };
    for (NSUInteger i = 0; i < sizeof(requirements)/sizeof(requirements[0]); ++i) {
        const struct SBCPUPeachDockRequirement *r = &requirements[i];
        if (!SBCPUPeachDockCheck(r->cls, r->selector, r->types, r->optional)) return NO;
    }
    return SBCPUPeachDockDPGroupReady(objc_getClass("SBIconDragManager"));
}
