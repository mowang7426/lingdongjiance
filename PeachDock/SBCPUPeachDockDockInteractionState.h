// Shared by Tweak.m and SBCPUPeachDockEdgeTransition.m. One edit policy for Dock layout,
// hit mapping and visual/spring suppression; never writes SB editing/model state.
#import <string.h>
static inline BOOL SBCPUPeachDockDockReadEditing(id list, BOOL *value) {
    if (!NSThread.isMainThread || !list || !value) return NO;
    Class dock = objc_getClass("SBDockIconListView");
    if (!dock || ![list isKindOfClass:dock]) return NO;
    @try {
        SEL selector = sel_registerName("isEditing");
        Method method = class_getInstanceMethod(object_getClass(list), selector);
        // UIView may supply a generic isEditing getter; only a Dock/list-specific
        // implementation is evidence of the SpringBoard local editing state.
        if (!method || method == class_getInstanceMethod(UIView.class, selector) ||
            method_getNumberOfArguments(method) != 2) return NO;
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        const char *result = signature.methodReturnType;
        if ((strcmp(result, "B") && strcmp(result, "c")) ||
            strcmp([signature getArgumentTypeAtIndex:0], "@") ||
            strcmp([signature getArgumentTypeAtIndex:1], ":")) return NO;
        *value = ((BOOL (*)(id, SEL))objc_msgSend)(list, selector);
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
static inline BOOL SBCPUPeachDockDockInteractionActive(id list) {
    if (!NSThread.isMainThread || !list) return NO;
    Class dock = objc_getClass("SBDockIconListView");
    if (!dock || ![list isKindOfClass:dock]) return NO;
    BOOL editing = NO;
    // A valid local answer is authoritative, INCLUDING NO on unlock/exit-edit.
    // The controller probe disagreed with the real Dock in the diag1 trace.
    if (SBCPUPeachDockDockReadEditing(list, &editing)) return editing;
    // Preserve the prior guarded controller probe only on an unknown local ABI;
    // do not guess a private drag-session getter or latch editing across calls.
    @try { return SBCPUPeachDockIconEditingActive(); }
    @catch (__unused NSException *exception) { return NO; }
}
