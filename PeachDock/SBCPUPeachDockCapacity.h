#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

// Included once by SBCPUPeachDock.m, after SBCPUPeachDockWeakOwner and the
// maximum-count constant. Never identify a Dock by its folder or old capacity.
static void *SBCPUPeachDockModelOwnerKey = &SBCPUPeachDockModelOwnerKey;
static NSHashTable *SBCPUPeachDockBoundLists;
static BOOL SBCPUPeachDockBindingModel;

static id SBCPUPeachDockReadModel(id list) {
    return ((id (*)(id, SEL))objc_msgSend)(list, @selector(model));
}

static void SBCPUPeachDockBindModel(id list, id model) {
    if (![NSThread isMainThread] || !model ||
        ![list isKindOfClass:objc_getClass("SBDockIconListView")] ||
        ![model isKindOfClass:objc_getClass("SBIconListModel")]) return;
    SBCPUPeachDockWeakOwner *owner = objc_getAssociatedObject(model, SBCPUPeachDockModelOwnerKey);
    if (!owner) owner = [SBCPUPeachDockWeakOwner new];
    owner.list = list;
    objc_setAssociatedObject(model, SBCPUPeachDockModelOwnerKey, owner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!SBCPUPeachDockBoundLists) SBCPUPeachDockBoundLists = [NSHashTable weakObjectsHashTable];
    [SBCPUPeachDockBoundLists addObject:list];
}

static BOOL SBCPUPeachDockOwnsModel(id model) {
    if (![NSThread isMainThread] || SBCPUPeachDockBindingModel) return NO;
    SBCPUPeachDockWeakOwner *owner = objc_getAssociatedObject(model, SBCPUPeachDockModelOwnerKey);
    id list = owner.list;
    if (!list) return NO;
    // A recycled model ceases to be Dock-owned immediately, even if the old
    // association survives. Weak owner avoids a model/view retain cycle.
    SBCPUPeachDockBindingModel = YES;
    id current = nil;
    @try { current = SBCPUPeachDockReadModel(list); }
    @finally { SBCPUPeachDockBindingModel = NO; }
    return current == model;
}

static id (*SBCPUPeachDockOriginalGetModel)(id, SEL);
static id SBCPUPeachDockHookGetModel(id self, SEL cmd) {
    id model = SBCPUPeachDockOriginalGetModel(self, cmd);
    if (!SBCPUPeachDockBindingModel) SBCPUPeachDockBindModel(self, model);
    return model;
}

static void (*SBCPUPeachDockOriginalSetModel)(id, SEL, id);
static void SBCPUPeachDockHookSetModel(id self, SEL cmd, id model) {
    // Do not change the old model or bypass SpringBoard's ownership transfer.
    SBCPUPeachDockOriginalSetModel(self, cmd, model);
    SBCPUPeachDockBindModel(self, SBCPUPeachDockReadModel(self));
}

static unsigned long long (*SBCPUPeachDockOriginalModelMaximum)(id, SEL);
static unsigned long long SBCPUPeachDockHookModelMaximum(id self, SEL cmd) {
    unsigned long long original = SBCPUPeachDockOriginalModelMaximum(self, cmd);
    return SBCPUPeachDockOwnsModel(self) ? MAX(original, SBCPUPeachDockMaximumDockIcons) : original;
}

static unsigned long long (*SBCPUPeachDockOriginalListMaximum)(id, SEL);
static unsigned long long SBCPUPeachDockHookListMaximum(id self, SEL cmd) {
    unsigned long long original = SBCPUPeachDockOriginalListMaximum(self, cmd);
    id model = SBCPUPeachDockReadModel(self);
    SBCPUPeachDockBindModel(self, model);
    return SBCPUPeachDockOwnsModel(model) ? MAX(original, SBCPUPeachDockMaximumDockIcons) : original;
}

// Read-only recovery evidence. Unknown/unbound is NOT proof of an empty Dock.
// Caller can refuse disable/uninstall without moving or deleting any icons.
static inline BOOL SBCPUPeachDockReadBoundCount(unsigned long long *count) {
    if (![NSThread isMainThread] || SBCPUPeachDockBoundLists.count == 0) return NO;
    unsigned long long largest = 0;
    BOOL observed = NO;
    for (id list in SBCPUPeachDockBoundLists) {
        observed = YES;
        id model = SBCPUPeachDockReadModel(list);
        if (!SBCPUPeachDockOwnsModel(model)) return NO;
        unsigned long long value = ((unsigned long long (*)(id, SEL))objc_msgSend)(model, @selector(numberOfIcons));
        largest = MAX(largest, value);
    }
    if (!observed) return NO;
    if (count) *count = largest;
    return YES;
}

static BOOL SBCPUPeachDockCapacityMethod(Class cls, const char *name, const char *types) {
    Method method = class_getInstanceMethod(cls, sel_registerName(name));
    if (!method) return NO;
    NSMethodSignature *a = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    NSMethodSignature *e = [NSMethodSignature signatureWithObjCTypes:types];
    if (!a || a.numberOfArguments != e.numberOfArguments || strcmp(a.methodReturnType, e.methodReturnType)) return NO;
    for (NSUInteger i = 0; i < a.numberOfArguments; ++i)
        if (strcmp([a getArgumentTypeAtIndex:i], [e getArgumentTypeAtIndex:i])) return NO;
    return YES;
}
static BOOL SBCPUPeachDockCapacityReady(Class dockClass, Class modelClass) {
    return SBCPUPeachDockCapacityMethod(dockClass, "model", "@@:") &&
        SBCPUPeachDockCapacityMethod(dockClass, "setModel:", "v@:@") &&
        SBCPUPeachDockCapacityMethod(dockClass, "maximumIconCount", "Q@:") &&
        SBCPUPeachDockCapacityMethod(modelClass, "maxNumberOfIcons", "Q@:") &&
        SBCPUPeachDockCapacityMethod(modelClass, "numberOfIcons", "Q@:");
}
static void SBCPUPeachDockInstallCapacity(Class dockClass, Class modelClass) {
    // Also enforce the local group contract when invoked by a host test.
    if (!SBCPUPeachDockCapacityReady(dockClass, modelClass)) return;
    MSHookMessageEx(dockClass, @selector(model), (IMP)SBCPUPeachDockHookGetModel, (IMP *)&SBCPUPeachDockOriginalGetModel);
    MSHookMessageEx(dockClass, @selector(setModel:), (IMP)SBCPUPeachDockHookSetModel, (IMP *)&SBCPUPeachDockOriginalSetModel);
    MSHookMessageEx(modelClass, @selector(maxNumberOfIcons), (IMP)SBCPUPeachDockHookModelMaximum, (IMP *)&SBCPUPeachDockOriginalModelMaximum);
    MSHookMessageEx(dockClass, @selector(maximumIconCount), (IMP)SBCPUPeachDockHookListMaximum, (IMP *)&SBCPUPeachDockOriginalListMaximum);
}
