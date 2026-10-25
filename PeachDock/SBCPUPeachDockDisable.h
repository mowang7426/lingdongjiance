#import "SBCPUPeachDockDisableIPC.h"
// Sources: iOS 16 SBIconListViewDragDelegate / SBIconViewDragDelegate protocols.
// A transaction holds the runtime layout intact. Only admission is suspended;
// no icon deletion/migration and no whole-screen touch interception occurs.
static NSString *SBCPUPeachDockDisableNonce;
static BOOL SBCPUPeachDockDisableCommitted;
static NSMutableSet *SBCPUPeachDockCancelledNonces;
static NSMutableSet *SBCPUPeachDockActiveDrags;
static NSHashTable *SBCPUPeachDockObservedDrops;
static CFMessagePortRef SBCPUPeachDockDisablePort;
static BOOL SBCPUPeachDockAdmissionLocked(void) { return SBCPUPeachDockDisableNonce != nil; }
static BOOL SBCPUPeachDockDisableIsDock(id list) {
    return [list isKindOfClass:objc_getClass("SBDockIconListView")];
}
static BOOL (*SBCPUPeachDockOriginalCanBegin)(id,SEL,id);
static BOOL SBCPUPeachDockDisableCanBegin(id self, SEL cmd, id view) {
    // Conservatively pause icon drags while pending/committed, not the screen.
    return !SBCPUPeachDockAdmissionLocked() && SBCPUPeachDockOriginalCanBegin(self,cmd,view);
}
static void (*SBCPUPeachDockOriginalDragBegin)(id,SEL,id,id);
static void SBCPUPeachDockDisableDragBegin(id self,SEL cmd,id view,id session) {
    if (session) [SBCPUPeachDockActiveDrags addObject:session];
    SBCPUPeachDockOriginalDragBegin(self,cmd,view,session);
}
static void (*SBCPUPeachDockOriginalDragEnd)(id,SEL,id,id,unsigned long long);
static void SBCPUPeachDockDisableDragEnd(id self,SEL cmd,id view,id session,unsigned long long operation) {
    SBCPUPeachDockOriginalDragEnd(self,cmd,view,session,operation);
    if (session) [SBCPUPeachDockActiveDrags removeObject:session];
}
static BOOL (*SBCPUPeachDockOriginalCanDrop)(id,SEL,id,id);
static BOOL SBCPUPeachDockDisableCanDrop(id self,SEL cmd,id list,id session) {
    if (session) [SBCPUPeachDockObservedDrops addObject:session];
    if (SBCPUPeachDockAdmissionLocked() && SBCPUPeachDockDisableIsDock(list)) return NO;
    return SBCPUPeachDockOriginalCanDrop(self,cmd,list,session);
}
static id (*SBCPUPeachDockOriginalDropUpdate)(id,SEL,id,id);
static id SBCPUPeachDockDisableDropUpdate(id self,SEL cmd,id list,id session) {
    if (session) [SBCPUPeachDockObservedDrops addObject:session];
    if (SBCPUPeachDockAdmissionLocked() && SBCPUPeachDockDisableIsDock(list))
        return [[UIDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    return SBCPUPeachDockOriginalDropUpdate(self,cmd,list,session);
}
static void (*SBCPUPeachDockOriginalPerformDrop)(id,SEL,id,id);
static void SBCPUPeachDockDisablePerformDrop(id self,SEL cmd,id list,id session) {
    if (session) [SBCPUPeachDockObservedDrops addObject:session];
    if (SBCPUPeachDockAdmissionLocked() && SBCPUPeachDockDisableIsDock(list)) return;
    SBCPUPeachDockOriginalPerformDrop(self,cmd,list,session);
}
static BOOL SBCPUPeachDockDisableReady(void) {
    Class manager = objc_getClass("SBIconDragManager");
    return SBCPUPeachDockCapacityMethod(manager,"iconViewCanBeginDrags:","B@:@") &&
        SBCPUPeachDockCapacityMethod(manager,"iconViewWillBeginDrag:session:","v@:@@") &&
        SBCPUPeachDockCapacityMethod(manager,"iconView:didEndDragSession:withOperation:","v@:@@Q") &&
        SBCPUPeachDockCapacityMethod(manager,"iconListView:canHandleIconDropSession:","B@:@@") &&
        SBCPUPeachDockCapacityMethod(manager,"iconListView:iconDropSessionDidUpdate:","@@:@@") &&
        SBCPUPeachDockCapacityMethod(manager,"iconListView:performIconDrop:","v@:@@");
}
static BOOL SBCPUPeachDockDisableIdle(void) {
    if (SBCPUPeachDockActiveDrags.count || SBCPUPeachDockObservedDrops.allObjects.count) return NO;
    for (id list in SBCPUPeachDockBoundLists) {
        BOOL editing = YES;
        if (!SBCPUPeachDockDockReadEditing(list, &editing) || editing) return NO;
        UIScrollView *scroll = SBCPUPeachDockScrollView(list);
        if (scroll.dragging || scroll.decelerating || scroll.tracking) return NO;
        for (UIGestureRecognizer *gesture in [(UIView *)list gestureRecognizers])
            if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) return NO;
    }
    return YES;
}
// -1 = unknown (must keep lock), 0 = confirmed enabled, 1 = disabled.
static int SBCPUPeachDockPersistedDisabled(void) {
    if (!CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) return -1;
    id value = CFBridgingRelease(CFPreferencesCopyValue(CFSTR("peachDockEnabled"),
        CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    if (![value isKindOfClass:NSNumber.class]) return -1;
    return [value boolValue] ? 0 : 1;
}
static NSDictionary *SBCPUPeachDockDisableHandle(NSDictionary *request) {
    NSString *nonce = request[@"nonce"], *phase = request[@"phase"];
    if (!NSThread.isMainThread || ![nonce isKindOfClass:NSString.class] || nonce.length != 36 ||
        ![[NSUUID alloc] initWithUUIDString:nonce]) return @{@"status":@"invalid"};
    NSString *status = @"denied";
    if ([phase isEqual:@"cancel"]) {
        [SBCPUPeachDockCancelledNonces addObject:nonce];
        if ([nonce isEqual:SBCPUPeachDockDisableNonce] && !SBCPUPeachDockDisableCommitted) {
            // Lost commit reply must never allow a persisted disable to unlock.
            int persisted = SBCPUPeachDockPersistedDisabled();
            if (persisted == 1) SBCPUPeachDockDisableCommitted = YES;
            else if (persisted == 0) SBCPUPeachDockDisableNonce = nil;
        }
        status = SBCPUPeachDockDisableCommitted ? @"committed" :
            ([nonce isEqual:SBCPUPeachDockDisableNonce] ? @"locked" : @"cancelled");
    } else if ([phase isEqual:@"prepare"]) {
        unsigned long long count = 0;
        if ([SBCPUPeachDockCancelledNonces containsObject:nonce]) status = @"cancelled";
        else if (SBCPUPeachDockAdmissionLocked()) status = @"locked";
        else if (!SBCPUPeachDockReadBoundCount(&count)) status = @"unknown";
        else if (count > 4) status = @"overflow";
        else if (!SBCPUPeachDockDisableIdle()) status = @"busy";
        else {
            // Same main-queue turn: lock BEFORE sending permission to persist.
            SBCPUPeachDockDisableNonce = [nonce copy];
            status = @"prepared";
        }
    } else if ([phase isEqual:@"commit"] && [nonce isEqual:SBCPUPeachDockDisableNonce]) {
        if (SBCPUPeachDockPersistedDisabled() == 1) {
            SBCPUPeachDockDisableCommitted = YES;
            status = @"committed";
        } else status = @"write-not-observed";
    }
    return @{@"nonce":nonce, @"status":status};
}
static CFDataRef SBCPUPeachDockDisableReceive(CFMessagePortRef port, SInt32 message,
        CFDataRef data, void *info) {
    (void)port; (void)info;
    if (message != 1 || !data || CFDataGetLength(data) > 1024) return NULL;
    @try {
        id request = [NSJSONSerialization JSONObjectWithData:(__bridge NSData *)data options:0 error:nil];
        if (![request isKindOfClass:NSDictionary.class]) return NULL;
        NSDictionary *reply = SBCPUPeachDockDisableHandle(request);
        return CFBridgingRetain([NSJSONSerialization dataWithJSONObject:reply options:0 error:nil]);
    } @catch (__unused NSException *exception) {
        // Never issue permission on an unreadable/private-runtime exception.
        return NULL;
    }
}
static BOOL SBCPUPeachDockInstallDisable(void) {
    if (!SBCPUPeachDockDisableReady()) return NO;
    SBCPUPeachDockCancelledNonces = [NSMutableSet new];
    SBCPUPeachDockActiveDrags = [NSMutableSet new];
    SBCPUPeachDockObservedDrops = [NSHashTable weakObjectsHashTable];
    CFMessagePortContext context = {0, NULL, NULL, NULL, NULL};
    SBCPUPeachDockDisablePort = CFMessagePortCreateLocal(kCFAllocatorDefault,
        SBCPU_PEACH_DISABLE_PORT, SBCPUPeachDockDisableReceive, &context, NULL);
    if (!SBCPUPeachDockDisablePort) return NO;
    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, SBCPUPeachDockDisablePort, 0);
    if (!source) { CFRelease(SBCPUPeachDockDisablePort); SBCPUPeachDockDisablePort = NULL; return NO; }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    Class manager = objc_getClass("SBIconDragManager");
#define SBCPU_PEACH_DISABLE_HOOK(selector, hook, original) \
    MSHookMessageEx(manager, sel_registerName(selector), (IMP)hook, (IMP *)&original)
    SBCPU_PEACH_DISABLE_HOOK("iconViewCanBeginDrags:", SBCPUPeachDockDisableCanBegin, SBCPUPeachDockOriginalCanBegin);
    SBCPU_PEACH_DISABLE_HOOK("iconViewWillBeginDrag:session:", SBCPUPeachDockDisableDragBegin, SBCPUPeachDockOriginalDragBegin);
    SBCPU_PEACH_DISABLE_HOOK("iconView:didEndDragSession:withOperation:", SBCPUPeachDockDisableDragEnd, SBCPUPeachDockOriginalDragEnd);
    SBCPU_PEACH_DISABLE_HOOK("iconListView:canHandleIconDropSession:", SBCPUPeachDockDisableCanDrop, SBCPUPeachDockOriginalCanDrop);
    SBCPU_PEACH_DISABLE_HOOK("iconListView:iconDropSessionDidUpdate:", SBCPUPeachDockDisableDropUpdate, SBCPUPeachDockOriginalDropUpdate);
    SBCPU_PEACH_DISABLE_HOOK("iconListView:performIconDrop:", SBCPUPeachDockDisablePerformDrop, SBCPUPeachDockOriginalPerformDrop);
#undef SBCPU_PEACH_DISABLE_HOOK
    return YES;
}
