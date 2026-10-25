// Included after SBCPUPeachDockDockDropMapping.h. Correct only the observed ordinary-app
// preview contract: content-space icon.center was treated as list-space.
// No layout/model/alpha/assertion writes, no dependency on diagnostic budgets.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface SBCPUPeachDockDockDropPreviewContext : NSObject
@property(nonatomic, weak) UIView *list, *view;
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) id manager, item, icon;
@property(nonatomic) BOOL ready;
@end
@implementation SBCPUPeachDockDockDropPreviewContext
@end
static char SBCPUPeachDockDPItemKey, SBCPUPeachDockDPViewKey;
static BOOL SBCPUPeachDockDPMethod(Class cls, SEL sel, const char *result, const char *const *args, NSUInteger count) {
    @try {
        Method m=class_getInstanceMethod(cls,sel);
        if (!m || method_getNumberOfArguments(m)!=count+2) return NO;
        NSMethodSignature *s=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
        if (strcmp(s.methodReturnType,result) || strcmp([s getArgumentTypeAtIndex:0],"@") ||
            strcmp([s getArgumentTypeAtIndex:1],":")) return NO;
        for(NSUInteger i=0;i<count;++i) if(strcmp([s getArgumentTypeAtIndex:i+2],args[i])) return NO;
        return YES;
    } @catch (__unused NSException *e) { return NO; }
}
static BOOL SBCPUPeachDockDPReadIcon(id view, id *icon) {
    if (!NSThread.isMainThread || !view || !icon) return NO;
    @try {
        SEL sel=sel_registerName("icon");
        if (!SBCPUPeachDockDPMethod(object_getClass(view),sel,"@",NULL,0)) return NO;
        *icon=((id(*)(id,SEL))objc_msgSend)(view,sel);
        return YES;
    } @catch (__unused NSException *e) { return NO; }
}
static BOOL SBCPUPeachDockDPPointFinite(CGPoint p) { return isfinite(p.x)&&isfinite(p.y); }
static BOOL SBCPUPeachDockDPNear(CGPoint a, CGPoint b) {
    return SBCPUPeachDockDPPointFinite(a)&&SBCPUPeachDockDPPointFinite(b)&&fabs(a.x-b.x)<1e-6&&fabs(a.y-b.y)<1e-6;
}
static BOOL SBCPUPeachDockDPBoundsValid(CGRect b) {
    return isfinite(b.origin.x)&&isfinite(b.origin.y)&&isfinite(b.size.width)&&isfinite(b.size.height)&&b.size.width>0&&b.size.height>0;
}
static BOOL SBCPUPeachDockDPEligible(id list, id view) {
    if (!NSThread.isMainThread || !list || !view) return NO;
    @try {
        Class dock=objc_getClass("SBDockIconListView"),iconView=objc_getClass("SBIconView");
        BOOL editing=NO;
        if (!dock || !iconView || ![list isKindOfClass:dock] || ![view isKindOfClass:iconView] ||
            !SBCPUPeachDockDockReadEditing(list,&editing) || !editing) return NO;
        UIView *lv=list, *iv=view, *content=SBCPUPeachDockContentView(list), *clip=SBCPUPeachDockClipView(list);
        UIScrollView *scroll=SBCPUPeachDockScrollView(list);
        return [content isKindOfClass:UIView.class] && [clip isKindOfClass:UIView.class] &&
            [scroll isKindOfClass:UIScrollView.class] && content.superview==scroll && clip.superview==lv &&
            (scroll.superview==clip || [SBCPUPeachDockEdgeTransition sbcpu_peach_dock_listView:lv ownsScrollView:scroll contentView:content clipView:clip]) &&
            objc_getAssociatedObject(content,SBCPUPeachDockOwnerListKey)==list &&
            SBCPUPeachDockDPBoundsValid(lv.bounds) && SBCPUPeachDockDPBoundsValid(scroll.bounds) && SBCPUPeachDockDPBoundsValid(content.bounds) && SBCPUPeachDockDPBoundsValid(clip.bounds) &&
            SBCPUPeachDockDPPointFinite(scroll.contentOffset) && SBCPUPeachDockDropWantsMapping(list) &&
            iv.superview==content && iv.window && iv.window==lv.window && CGAffineTransformIsIdentity(iv.transform);
    } @catch (__unused NSException *e) { return NO; }
}
// Each pending record is its own generation token. Both directions must still
// point to it after ANY native/public callback. No system object is kept alive.
static void SBCPUPeachDockDPInvalidate(SBCPUPeachDockDockDropPreviewContext *c) {
    @try {
        if (![c isKindOfClass:SBCPUPeachDockDockDropPreviewContext.class]) return;
        c.ready=NO;
        id item=c.item; UIView *view=c.view;
        if (item && objc_getAssociatedObject(item,&SBCPUPeachDockDPItemKey)==c) objc_setAssociatedObject(item,&SBCPUPeachDockDPItemKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (view && objc_getAssociatedObject(view,&SBCPUPeachDockDPViewKey)==c) objc_setAssociatedObject(view,&SBCPUPeachDockDPViewKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) { /* metadata must not change native outcome */ }
}
static SBCPUPeachDockDockDropPreviewContext *SBCPUPeachDockDPBegin(id manager,id list,id view,id item) {
    if (!NSThread.isMainThread || !item) return nil;
    @try {
        SBCPUPeachDockDPInvalidate(objc_getAssociatedObject(item,&SBCPUPeachDockDPItemKey));
        if (view) SBCPUPeachDockDPInvalidate(objc_getAssociatedObject(view,&SBCPUPeachDockDPViewKey));
        if (!manager) return nil;
        SBCPUPeachDockDockDropPreviewContext *c=[SBCPUPeachDockDockDropPreviewContext new];
        c.manager=manager; c.list=list; c.view=view; c.item=item;
        objc_setAssociatedObject(item,&SBCPUPeachDockDPItemKey,c,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (view) objc_setAssociatedObject(view,&SBCPUPeachDockDPViewKey,c,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        id icon=nil;
        if (!SBCPUPeachDockDPEligible(list,view) || !SBCPUPeachDockDPReadIcon(view,&icon) || !icon ||
            objc_getAssociatedObject(item,&SBCPUPeachDockDPItemKey)!=c || objc_getAssociatedObject(view,&SBCPUPeachDockDPViewKey)!=c) {
            SBCPUPeachDockDPInvalidate(c); return nil;
        }
        c.icon=icon; c.window=[(UIView *)view window];
        return c;
    } @catch (__unused NSException *e) { return nil; }
}
static BOOL SBCPUPeachDockDPLive(SBCPUPeachDockDockDropPreviewContext *c,id manager,id list,id item,BOOL requireReady) {
    if (!NSThread.isMainThread || !manager || !list || !item) return NO;
    @try {
        if (![c isKindOfClass:SBCPUPeachDockDockDropPreviewContext.class] || (requireReady&&!c.ready) ||
            c.manager!=manager || c.item!=item || c.list!=list) return NO;
        UIView *view=c.view; id icon=nil;
        return view && c.icon && c.window && view.window==c.window && objc_getAssociatedObject(item,&SBCPUPeachDockDPItemKey)==c && objc_getAssociatedObject(view,&SBCPUPeachDockDPViewKey)==c &&
            SBCPUPeachDockDPEligible(list,view) && SBCPUPeachDockDPReadIcon(view,&icon) && icon==c.icon &&
            c.window && view.window==c.window && (!requireReady||c.ready) && c.manager==manager && c.list==list && c.item==item && c.view==view &&
            objc_getAssociatedObject(item,&SBCPUPeachDockDPItemKey)==c && objc_getAssociatedObject(view,&SBCPUPeachDockDPViewKey)==c;
    } @catch (__unused NSException *e) { return NO; }
}
// Identity-only tail check: no system/private/public getters after the final
// geometry snapshot. In particular, do not call icon again at that boundary.
static BOOL SBCPUPeachDockDPTokenCurrent(SBCPUPeachDockDockDropPreviewContext *c,id manager,id list,id item) {
    @try {
        UIView *view=c.view;
        return c.ready && view && c.icon && c.window && c.manager==manager && c.list==list && c.item==item &&
            objc_getAssociatedObject(item,&SBCPUPeachDockDPItemKey)==c && objc_getAssociatedObject(view,&SBCPUPeachDockDPViewKey)==c;
    } @catch (__unused NSException *e) { return NO; }
}
static id SBCPUPeachDockDPCorrectPreview(id manager,id list,id item,id proposed,id original,SBCPUPeachDockDockDropPreviewContext *c) {
    if (!NSThread.isMainThread || !list || !item || !original || original!=proposed) return original;
    @try {
        if (!SBCPUPeachDockDPLive(c,manager,list,item,YES) || ![original isKindOfClass:UITargetedDragPreview.class]) return original;
        UIView *view=c.view, *parent=view.superview;
        UITargetedDragPreview *preview=original;
        UIDragPreviewTarget *target=preview.target;
        if (![target isKindOfClass:UIDragPreviewTarget.class] || target.container!=view) return original;
        CGAffineTransform transform=target.transform;
        CGPoint targetCenter=target.center;
        if (!CGAffineTransformIsIdentity(transform)) return original;
        CGPoint parentCenter=view.center;
        CGPoint listCenter=[list convertPoint:parentCenter fromView:parent];
        CGPoint nativePattern=[view convertPoint:parentCenter fromView:list];
        CGPoint corrected=[view convertPoint:listCenter fromView:list];
        CGRect bounds=view.bounds;
        if (!SBCPUPeachDockDPBoundsValid(bounds) || !SBCPUPeachDockDPPointFinite(parentCenter)||!SBCPUPeachDockDPPointFinite(listCenter) ||
            !SBCPUPeachDockDPNear(targetCenter,nativePattern) ||
            !SBCPUPeachDockDPNear(corrected,CGPointMake(CGRectGetMidX(bounds),CGRectGetMidY(bounds)))) return original;
        // Identity on page one/already correct means no allocation and EXACT
        // native pointer preserved. Do not re-center an arbitrary custom target.
        if (SBCPUPeachDockDPNear(targetCenter,corrected)) return original;
        UIView *previewView=preview.view; CGSize size=preview.size;
        if (![previewView isKindOfClass:UIView.class] || !isfinite(size.width)||!isfinite(size.height)||size.width<=0||size.height<=0 ||
            !SBCPUPeachDockDPLive(c,manager,list,item,YES)) return original;
        UIDragPreviewTarget *newTarget=[[UIDragPreviewTarget alloc] initWithContainer:view center:corrected transform:transform];
        UITargetedDragPreview *result=[preview retargetedPreviewWithTarget:newTarget];
        if (![result isKindOfClass:UITargetedDragPreview.class] || result.view!=previewView || !CGSizeEqualToSize(result.size,size)) return original;
        UIDragPreviewTarget *resultTarget=result.target;
        if (![resultTarget isKindOfClass:UIDragPreviewTarget.class] || resultTarget.container!=view ||
            !SBCPUPeachDockDPNear(resultTarget.center,corrected) || !CGAffineTransformEqualToTransform(resultTarget.transform,transform)) return original;
        // This Live may invoke icon/eligibility getters. They MUST precede the
        // final geometry snapshot: a callback can change bounds without changing
        // either the icon or association token. No such getters follow it.
        if (!SBCPUPeachDockDPLive(c,manager,list,item,YES) ||
            !CGRectEqualToRect(bounds,view.bounds) || !SBCPUPeachDockDPNear(parentCenter,view.center) ||
            view.superview!=parent || view.window!=c.window || [(UIView *)list window]!=c.window ||
            !CGAffineTransformIsIdentity(view.transform) ||
            !SBCPUPeachDockDPNear(listCenter,[list convertPoint:view.center fromView:parent]) ||
            !SBCPUPeachDockDPTokenCurrent(c,manager,list,item)) return original;
        return result;
    } @catch (__unused NSException *e) { return original; }
}
static void (*SBCPUPeachDockDPOriginalWillUse)(id,SEL,id,id,id);
static id (*SBCPUPeachDockDPOriginalPreview)(id,SEL,id,id,id);
static void SBCPUPeachDockDPWillUse(id self,SEL cmd,id list,id view,id item) {
    SBCPUPeachDockDockDropPreviewContext *c=SBCPUPeachDockDPBegin(self,list,view,item);
    BOOL completed=NO;
    @try {
        SBCPUPeachDockDPOriginalWillUse(self,cmd,list,view,item);
        completed=YES;
    } @finally {
        // Preserve the exact native exception. Failed/invalid calls never leave
        // a previous successful candidate for this item or selected view.
        if (completed && SBCPUPeachDockDPLive(c,self,list,item,NO)) c.ready=YES;
        else SBCPUPeachDockDPInvalidate(c);
        if (!completed && NSThread.isMainThread && item) {
            @try { SBCPUPeachDockDPInvalidate(objc_getAssociatedObject(item,&SBCPUPeachDockDPItemKey)); }
            @catch (__unused NSException *e) { }
        }
    }
}
static id SBCPUPeachDockDPPreview(id self,SEL cmd,id list,id item,id proposed) {
    SBCPUPeachDockDockDropPreviewContext *c=nil;
    if (NSThread.isMainThread && item) {
        @try { c=objc_getAssociatedObject(item,&SBCPUPeachDockDPItemKey); }
        @catch (__unused NSException *e) { }
    }
    // Original is called exactly once, outside our exception-catching correction.
    id original=SBCPUPeachDockDPOriginalPreview(self,cmd,list,item,proposed);
    return SBCPUPeachDockDPCorrectPreview(self,list,item,proposed,original,c);
}
static BOOL SBCPUPeachDockDPGroupReady(Class manager) {
    const char *args[]={"@","@","@"};
    return SBCPUPeachDockDPMethod(manager,sel_registerName("iconListView:willUseIconView:forDroppingIconDragItem:"),"v",args,3) &&
        SBCPUPeachDockDPMethod(manager,sel_registerName("iconListView:previewForDroppingIconDragItem:proposedPreview:"),"@",args,3);
}
static void SBCPUPeachDockInstallDropPreviewMapping(void) {
    Class manager=objc_getClass("SBIconDragManager");
    BOOL ready=SBCPUPeachDockDPGroupReady(manager);
    if (ready) {
        MSHookMessageEx(manager,sel_registerName("iconListView:willUseIconView:forDroppingIconDragItem:"),(IMP)SBCPUPeachDockDPWillUse,(IMP *)&SBCPUPeachDockDPOriginalWillUse);
        MSHookMessageEx(manager,sel_registerName("iconListView:previewForDroppingIconDragItem:proposedPreview:"),(IMP)SBCPUPeachDockDPPreview,(IMP *)&SBCPUPeachDockDPOriginalPreview);
    }
}
