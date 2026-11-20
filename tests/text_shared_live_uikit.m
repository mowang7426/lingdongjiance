// Real UIKit glyph/mask/cache code; CALayer substitutes private backdrop ONLY.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../SBCPUTextBackdropLabel.h"
#import "../SBCPUTextMemory.h"
#import "../SBCPUTextOnlyTypography.h"
#import "SBCPUMem5TextBackdropLabel.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static NSMutableArray *measurements;
static NSUInteger strictFailures, quantizedCases, parentNegativeControls;
static NSMutableArray *diagnostics;
static NSData *alpha(CGImageRef image) {
    size_t w=CGImageGetWidth(image), h=CGImageGetHeight(image);
    NSMutableData *rgba=[NSMutableData dataWithLength:w*h*4], *out=[NSMutableData dataWithLength:w*h];
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(rgba.mutableBytes,w,h,8,w*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    assert(c); CGContextDrawImage(c,CGRectMake(0,0,w,h),image);
    for (size_t i=0;i<w*h;i++) ((uint8_t *)out.mutableBytes)[i]=((uint8_t *)rgba.mutableBytes)[4*i+3];
    CGContextRelease(c); CGColorSpaceRelease(space); return out;
}
static UIImage *render(CALayer *layer, CGSize size, CGPoint offset, CGFloat scale) {
    UIGraphicsBeginImageContextWithOptions(size,NO,scale);
    // A ROOT render draws its coordinates directly, not its parent placement.
    // Normalize nonzero bounds once; the independent parent-composition check
    // below must also pass, so this exporter cannot hide a misplaced mask.
    CGContextTranslateCTM(UIGraphicsGetCurrentContext(),offset.x-layer.bounds.origin.x,offset.y-layer.bounds.origin.y);
    CGContextClipToRect(UIGraphicsGetCurrentContext(),layer.bounds);
    [layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image;
}
static CGRect imageInk(UIImage *image, CGFloat scale) {
    NSData *a=alpha(image.CGImage); const uint8_t *p=(const uint8_t *)a.bytes;
    size_t w=CGImageGetWidth(image.CGImage), h=CGImageGetHeight(image.CGImage);
    size_t x0=w,y0=h,x1=0,y1=0;
    for(size_t y=0;y<h;y++) for(size_t x=0;x<w;x++) if(p[y*w+x]) {
        x0=MIN(x0,x); y0=MIN(y0,y); x1=MAX(x1,x+1); y1=MAX(y1,y+1);
    }
    return x1>x0 && y1>y0 ? CGRectMake(x0/scale,y0/scale,(x1-x0)/scale,(y1-y0)/scale) : CGRectNull;
}
static UIImage *renderHostCoordinates(CALayer *layer, CGSize size, CGFloat scale, CGRect clip) {
    UIGraphicsBeginImageContextWithOptions(size,NO,scale);
    CGContextClipToRect(UIGraphicsGetCurrentContext(),clip);
    [layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *im=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return im;
}
static UIImage *parentComposedMask(CALayer *backdrop, CGSize size, CGFloat scale) {
    CALayer *root=[CALayer layer], *carrier=[CALayer layer], *mask=backdrop.mask;
    root.bounds=(CGRect){CGPointZero,size};
    carrier.bounds=backdrop.bounds; carrier.anchorPoint=backdrop.anchorPoint;
    carrier.position=backdrop.position; carrier.masksToBounds=YES;
    assert(CGRectEqualToRect(mask.frame,backdrop.bounds));
    // CPU renderInContext does not reliably exercise layer.mask. Reparent the
    // SAME mask as an ordinary child without changing its geometry, to exercise
    // CA's actual bounds/anchor/position transform under the backdrop surrogate.
    backdrop.mask=nil; [carrier addSublayer:mask]; [root addSublayer:carrier];
    UIImage *result=render(root,size,CGPointZero,scale);
    [mask removeFromSuperlayer]; backdrop.mask=mask;
    return result;
}
static NSDictionary *diff(UIImage *a, UIImage *b, CGFloat scale) {
    NSData *aa=alpha(a.CGImage), *bb=alpha(b.CGImage); assert(aa.length==bb.length);
    const uint8_t *x=(const uint8_t *)aa.bytes, *y=(const uint8_t *)bb.bytes;
    NSUInteger count=0,total=0,max=0,sa=0,sb=0;
    for(NSUInteger i=0;i<aa.length;i++) { NSUInteger d=abs((int)x[i]-(int)y[i]);
        if(d) count++; total+=d;max=MAX(max,d);sa+=x[i];sb+=y[i]; }
    return @{@"pixels":@(aa.length),@"different_pixels":@(count),@"max_delta":@(max),@"total_absolute_delta":@(total),
        @"actual_total_alpha":@(sa),@"reference_total_alpha":@(sb),@"actual_bbox":NSStringFromCGRect(imageInk(a,scale)),
        @"reference_bbox":NSStringFromCGRect(imageInk(b,scale))};
}
// A crop may alter 8-bit coverage rounding, but only at pixels where
// the pinned mem5 crop itself differs from the exact full-host baseline.
// The candidate must be one of the two mem5 values at every pixel.
static BOOL matchesMem5Crop(UIImage *candidate, UIImage *crop, UIImage *full) {
    NSData *ca=alpha(candidate.CGImage), *cr=alpha(crop.CGImage), *fu=alpha(full.CGImage);
    assert(ca.length==cr.length && cr.length==fu.length);
    const uint8_t *c=(const uint8_t *)ca.bytes, *r=(const uint8_t *)cr.bytes, *f=(const uint8_t *)fu.bytes;
    for (NSUInteger i=0;i<ca.length;i++) if(c[i]!=r[i] && (c[i]!=f[i] || abs((int)r[i]-(int)f[i])!=1)) return NO;
    return YES;
}
// CPU renderInContext can rasterize a window-attached CATextLayer and a
// fresh detached CATextLayer differently inside a clipped carrier. Freeze
// each side's independently exported native glyph pixels at 1:1 before the
// CA parent test. Only geometry/properties are copied from each real tree;
// do not derive any candidate placement from the reference or vice versa.
static CALayer *geometryCopy(CALayer *source) {
    CALayer *copy=[CALayer layer];
    copy.bounds=source.bounds; copy.anchorPoint=source.anchorPoint; copy.position=source.position;
    copy.transform=source.transform; copy.sublayerTransform=source.sublayerTransform;
    copy.opacity=source.opacity; copy.hidden=source.hidden; copy.masksToBounds=source.masksToBounds;
    copy.contentsScale=source.contentsScale;
    return copy;
}
static CALayer *pixelParent(CALayer *source, NSArray<UIImage *> *images) {
    CALayer *copy=geometryCopy(source), *mask=geometryCopy(source.mask);
    assert(images.count==source.mask.sublayers.count);
    NSUInteger i=0;
    for (CALayer *leaf in source.mask.sublayers) {
        UIImage *im=images[i++]; CALayer *raster=geometryCopy(leaf);
        raster.contents=(__bridge id)im.CGImage;
        raster.contentsGravity=kCAGravityTopLeft;
        [mask addSublayer:raster];
    }
    copy.mask=mask; return copy;
}
static void syntheticCoordinates(void) {
    for (int scale=1;scale<=3;scale++) {
        CALayer *backdrop=[CALayer layer], *mask=[CALayer layer], *ink=[CALayer layer];
        backdrop.anchorPoint=CGPointZero; backdrop.frame=CGRectMake(20,3,159,13);
        mask.anchorPoint=CGPointZero; mask.bounds=backdrop.frame; mask.position=CGPointZero;
        ink.frame=CGRectMake(21,4,2,2); ink.backgroundColor=UIColor.whiteColor.CGColor;
        [mask addSublayer:ink]; backdrop.mask=mask;
        CALayer *gold=[CALayer layer], *goldInk=[CALayer layer]; gold.bounds=CGRectMake(0,0,200,30);
        goldInk.frame=ink.frame; goldInk.backgroundColor=ink.backgroundColor; [gold addSublayer:goldInk];
        NSData *expected=alpha(render(gold,gold.bounds.size,CGPointZero,scale).CGImage);
        assert([expected isEqual:alpha(parentComposedMask(backdrop,gold.bounds.size,scale).CGImage)]);
        assert([expected isEqual:alpha(render(mask,gold.bounds.size,backdrop.frame.origin,scale).CGImage)]);
        // Reproduce the old export's extra (20,3) translation, independently of
        // any UILabel. It must NOT equal the parent-composed known rectangle.
        UIGraphicsBeginImageContextWithOptions(gold.bounds.size,NO,scale);
        CGContextTranslateCTM(UIGraphicsGetCurrentContext(),20,3);
        CGContextClipToRect(UIGraphicsGetCurrentContext(),CGRectMake(0,0,159,13));
        [mask renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *wrong=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
        assert(![expected isEqual:alpha(wrong.CGImage)]);
    }
    fprintf(stderr,"PASS synthetic parent coordinates and nonzero-bounds export negative control (1x/2x/3x)\n");
}
static SBCPUCapsuleBackdropLabel *add(SBCPUTextSlotHost *h, NSString *text, CGRect frame) {
    SBCPUCapsuleBackdropLabel *l=[[SBCPUCapsuleBackdropLabel alloc] initWithFrame:frame];
    l.textAlignment=NSTextAlignmentCenter; l.numberOfLines=1;
    l.lineBreakMode=NSLineBreakByClipping; l.clipsToBounds=YES;
    [l sbcpu_setTextOnlyPlainText:text font:[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular] color:UIColor.whiteColor];
    [h addSubview:l]; return l;
}
static void sync(SBCPUTextSlotHost *h, CGFloat s) { [h sbcpu_testSyncSharedAtScale:s]; }
static void assertSingle(SBCPUTextSlotHost *h) {
    CALayer *b=[h sbcpu_testSharedBackdrop]; assert(b && b.mask);
    NSUInteger n=0; for (CALayer *l in h.layer.sublayers) if (l==b) n++;
    assert(n==1);
    for (SBCPUCapsuleBackdropLabel *l in h.subviews) {
        assert(!l.realtimeInvertEnabled); // no competing per-label renderer
        for (CALayer *child in l.layer.sublayers) assert(!child.mask);
    }
}
static void parity(SBCPUTextSlotHost *h, CGFloat scale, NSString *name) {
    fprintf(stderr,"parity case: %s scale=%g\n",name.UTF8String,scale);
    sync(h,scale);
    if (![h sbcpu_testSharedBackdrop]) for (SBCPUCapsuleBackdropLabel *l in h.subviews)
        fprintf(stderr,"fallback slot frame=%s bounds=%s hidden=%d live=%d text=%s\n",NSStringFromCGRect(l.frame).UTF8String,NSStringFromCGRect(l.bounds).UTF8String,l.hidden,l.realtimeInvertEnabled,l.text.UTF8String);
    assertSingle(h);
    CALayer *b=[h sbcpu_testSharedBackdrop], *expected=[CALayer layer]; expected.frame=h.bounds;
    NSMutableArray<UIImage *> *currentPixels=[NSMutableArray array], *referencePixels=[NSMutableArray array];
    NSUInteger i=0; CGFloat oldBackdropArea=0; CGRect mem5Region=CGRectNull;
    for (SBCPUCapsuleBackdropLabel *l in h.subviews) {
        if (l.hidden || !l.text.length || CGRectIsEmpty(l.bounds)) continue;
        oldBackdropArea+=l.bounds.size.width*l.bounds.size.height;
        SBCPUMem5CapsuleBackdropLabel *m=[[SBCPUMem5CapsuleBackdropLabel alloc] initWithFrame:l.bounds];
        m.bounds=l.bounds; // avoid UIView frame-derived fractional bounds round trips
        m.font=l.font; m.text=l.text; m.attributedText=l.attributedText;
        m.textAlignment=l.textAlignment; m.numberOfLines=l.numberOfLines;
        m.lineBreakMode=l.lineBreakMode; m.adjustsFontSizeToFitWidth=l.adjustsFontSizeToFitWidth;
        m.minimumScaleFactor=l.minimumScaleFactor; m.baselineAdjustment=l.baselineAdjustment;
        m.semanticContentAttribute=l.semanticContentAttribute; m.clipsToBounds=l.clipsToBounds;
        m.realtimeInvertEnabled=YES; [m sbcpu_testSyncBackdropAtScale:scale];
        UIImage *im=[m sbcpu_testCopyAlphaMaskAtScale:scale]; assert(im);
        CGRect ink=imageInk(im,scale);
        if(!CGRectIsNull(ink)) mem5Region=CGRectUnion(mem5Region,CGRectOffset(ink,l.frame.origin.x,l.frame.origin.y));
        CALayer *actual=b.mask.sublayers[i++];
        UIImage *current=[l sbcpu_testCopyAlphaMaskAtScale:scale];
        assert(current && CGImageGetWidth(current.CGImage)==CGImageGetWidth(im.CGImage) &&
            CGImageGetHeight(current.CGImage)==CGImageGetHeight(im.CGImage) &&
            [alpha(current.CGImage) isEqual:alpha(im.CGImage)]);
        [currentPixels addObject:current]; [referencePixels addObject:im];
        assert(CGSizeEqualToSize(actual.bounds.size,l.bounds.size));
        // Reuse the pinned mem5 native alpha layer, preserving original bounds
        // and drawInContext behavior. No bitmap scaling in either implementation.
        CALayer *e=m.layer.sublayers.firstObject.mask; assert(e);
        m.layer.sublayers.firstObject.mask=nil;
        e.bounds=l.bounds; e.position=l.center;
        assert(CGRectEqualToRect(actual.bounds,e.bounds) && CGPointEqualToPoint(actual.position,e.position));
        assert(CGPointEqualToPoint(actual.anchorPoint,e.anchorPoint) && actual.contentsScale==e.contentsScale);
        assert(CATransform3DEqualToTransform(actual.transform,e.transform) &&
            CATransform3DEqualToTransform(actual.sublayerTransform,e.sublayerTransform));
        assert(actual.opacity==e.opacity && actual.hidden==e.hidden && actual.masksToBounds==e.masksToBounds);
        UILabel *ag=[actual valueForKey:@"glyphLabel"], *eg=[e valueForKey:@"glyphLabel"];
        if (ag && eg && !CGRectEqualToRect(ag.bounds,eg.bounds))
            fprintf(stderr,"glyph label bounds mismatch text=%s actual=%s mem5=%s\n",l.text.UTF8String,NSStringFromCGRect(ag.bounds).UTF8String,NSStringFromCGRect(eg.bounds).UTF8String);
        [expected addSublayer:e]; m.realtimeInvertEnabled=NO;
    }
    mem5Region=CGRectInset(mem5Region,-1.0/scale,-1.0/scale);
    CGFloat x=floor(CGRectGetMinX(mem5Region)*scale)/scale, y=floor(CGRectGetMinY(mem5Region)*scale)/scale;
    mem5Region=CGRectIntersection(h.bounds,CGRectMake(x,y,ceil(CGRectGetMaxX(mem5Region)*scale)/scale-x,
        ceil(CGRectGetMaxY(mem5Region)*scale)/scale-y));
    assert(CGRectEqualToRect(b.frame,mem5Region)); // independent mem5 ink + 1 physical pixel
    UIImage *actual=render(b.mask,h.bounds.size,b.frame.origin,scale);
    UIImage *fullRef=render(expected,h.bounds.size,CGPointZero,scale);
    UIImage *unclipped=renderHostCoordinates(b.mask,h.bounds.size,scale,h.bounds);
    // Preserve exact full-host native mem5 glyph parity, before adding ANY
    // crop topology to the reference. This is a separate mandatory assertion.
    assert([alpha(unclipped.CGImage) isEqual:alpha(fullRef.CGImage)]);
    // Build the reference crop solely from pinned mem5 alpha, in the same CA
    // coordinate topology. A bounds-origin/ancestry change alters CGContext
    // fractional glyph quantization even with identical clip rectangles.
    expected.anchorPoint=CGPointZero; expected.bounds=mem5Region;
    expected.position=CGPointZero; expected.contentsScale=scale;
    UIImage *ref=render(expected,h.bounds.size,mem5Region.origin,scale);
    CALayer *referenceBackdrop=[CALayer layer]; referenceBackdrop.anchorPoint=CGPointZero;
    referenceBackdrop.bounds=(CGRect){CGPointZero,mem5Region.size};
    referenceBackdrop.position=mem5Region.origin; referenceBackdrop.mask=expected;
    UIImage *nativeParent=parentComposedMask(b,h.bounds.size,scale);
    UIImage *nativeParentRef=parentComposedMask(referenceBackdrop,h.bounds.size,scale);
    assert(CATransform3DEqualToTransform(b.transform,referenceBackdrop.transform) &&
        CATransform3DEqualToTransform(b.sublayerTransform,referenceBackdrop.sublayerTransform) &&
        b.opacity==referenceBackdrop.opacity && b.hidden==referenceBackdrop.hidden &&
        b.masksToBounds==referenceBackdrop.masksToBounds && b.contentsScale==referenceBackdrop.contentsScale &&
        CATransform3DEqualToTransform(b.mask.transform,referenceBackdrop.mask.transform) &&
        CATransform3DEqualToTransform(b.mask.sublayerTransform,referenceBackdrop.mask.sublayerTransform) &&
        b.mask.opacity==referenceBackdrop.mask.opacity && b.mask.hidden==referenceBackdrop.mask.hidden &&
        b.mask.masksToBounds==referenceBackdrop.mask.masksToBounds &&
        b.mask.contentsScale==referenceBackdrop.mask.contentsScale);
    assert(b.mask.sublayers.count==referenceBackdrop.mask.sublayers.count);
    for (NSUInteger j=0;j<b.mask.sublayers.count;j++) {
        CALayer *candidateLeaf=b.mask.sublayers[j], *referenceLeaf=referenceBackdrop.mask.sublayers[j];
        assert(CGRectEqualToRect(candidateLeaf.bounds,referenceLeaf.bounds) &&
            CGPointEqualToPoint(candidateLeaf.position,referenceLeaf.position) &&
            CGPointEqualToPoint(candidateLeaf.anchorPoint,referenceLeaf.anchorPoint) &&
            CATransform3DEqualToTransform(candidateLeaf.transform,referenceLeaf.transform) &&
            CATransform3DEqualToTransform(candidateLeaf.sublayerTransform,referenceLeaf.sublayerTransform) &&
            candidateLeaf.opacity==referenceLeaf.opacity && candidateLeaf.hidden==referenceLeaf.hidden &&
            candidateLeaf.masksToBounds==referenceLeaf.masksToBounds &&
            candidateLeaf.contentsScale==referenceLeaf.contentsScale);
    }
    CALayer *pixelCandidate=pixelParent(b,currentPixels), *pixelRef=pixelParent(referenceBackdrop,referencePixels);
    UIImage *composed=parentComposedMask(pixelCandidate,h.bounds.size,scale);
    UIImage *composedRef=parentComposedMask(pixelRef,h.bounds.size,scale);
    assert(!CGRectIsNull(imageInk(composedRef,scale)));
    NSDictionary *direct=diff(actual,ref,scale), *parent=diff(composed,composedRef,scale);
    NSDictionary *mem5Crop=diff(ref,fullRef,scale), *candidateCrop=diff(actual,fullRef,scale);
    if ([name isEqualToString:@"production-window1-font8-bold0"]) {
        CALayer *leaf=pixelCandidate.mask.sublayers.firstObject; assert(leaf);
        CGPoint saved=leaf.position;
        leaf.position=CGPointMake(saved.x+1.0/scale,saved.y);
        UIImage *shifted=parentComposedMask(pixelCandidate,h.bounds.size,scale);
        assert(![alpha(shifted.CGImage) isEqual:alpha(composedRef.CGImage)]);
        leaf.position=saved; leaf.hidden=YES;
        UIImage *missing=parentComposedMask(pixelCandidate,h.bounds.size,scale);
        assert(![alpha(missing.CGImage) isEqual:alpha(composedRef.CGImage)]);
        leaf.hidden=NO;
        assert([alpha(parentComposedMask(pixelCandidate,h.bounds.size,scale).CGImage) isEqual:alpha(composed.CGImage)]);
        parentNegativeControls+=2;
        leaf=b.mask.sublayers.firstObject; saved=leaf.position;
        leaf.position=CGPointMake(saved.x+1.0/scale,saved.y);
        assert(!matchesMem5Crop(render(b.mask,h.bounds.size,b.frame.origin,scale),ref,fullRef));
        leaf.position=saved; leaf.hidden=YES;
        assert(!matchesMem5Crop(render(b.mask,h.bounds.size,b.frame.origin,scale),ref,fullRef));
        leaf.hidden=NO;
    }
    // Re-render the SAME pinned mem5 layers after returning to host bounds,
    // then crop/reparent again. No production glyph is involved in this control.
    expected.bounds=h.bounds; expected.position=CGPointZero;
    UIImage *selfFull=render(expected,h.bounds.size,CGPointZero,scale);
    expected.bounds=mem5Region;
    UIImage *selfCrop=render(expected,h.bounds.size,mem5Region.origin,scale);
    UIImage *selfParent=parentComposedMask(referenceBackdrop,h.bounds.size,scale);
    NSDictionary *selfFullDiff=diff(selfFull,fullRef,scale);
    NSDictionary *selfCropDiff=diff(selfCrop,ref,scale), *selfParentDiff=diff(selfParent,nativeParentRef,scale);
    BOOL directOK=matchesMem5Crop(actual,ref,fullRef);
    if (directOK && [direct[@"different_pixels"] unsignedIntegerValue]) quantizedCases++;
    if (!directOK || [parent[@"different_pixels"] unsignedIntegerValue]) strictFailures++;
    NSDictionary *diag=@{@"case":name,@"scale":@(scale),@"direct":direct,@"parent":parent,@"native_leaf_properties_exact":@YES,
        @"native_renderInContext_parent_diagnostic":diff(nativeParent,nativeParentRef,scale),
        @"mem5_crop_vs_full":mem5Crop,@"candidate_crop_vs_full":candidateCrop,
        @"mem5_self_full":selfFullDiff,@"mem5_self_crop":selfCropDiff,@"mem5_self_parent":selfParentDiff};
    [diagnostics addObject:diag];
    fprintf(stderr,"MATRIX %s\n",[[diag description] UTF8String]);
    assert(b.frame.size.width*b.frame.size.height<h.bounds.size.width*h.bounds.size.height);
    [measurements addObject:@{@"case":name,@"scale":@(scale),@"old_host_frame":NSStringFromCGRect(h.bounds),
        @"new_union_frame":NSStringFromCGRect(b.frame),@"old_area":@(h.bounds.size.width*h.bounds.size.height),
        @"union_area":@(b.frame.size.width*b.frame.size.height),@"mask_components":@(i),@"shared_backdrops":@1,
        @"old_per_label_backdrops":@(i),@"old_filter_recipe_entries":@(i*5),@"old_per_label_total_area":@(oldBackdropArea),
        @"filter_recipe_entries":@5,@"filters_gpu_exercised":@NO}];
}
static void productionLayout(UIWindow *window) {
    NSArray *rows=@[@"CPU 25%",@"3.46GHz",@"FPS816",@"BATT 85%",@"TEMP 42°",@"I 278mA",@"SIM1",@"SIM2",@"↑1.0MB/s",@"↓2.0MB/s",@"RAM 6.1GB"];
    const int sizes[]={8,13,18,24};
    for (int second=0;second<2;second++) for (int fs: sizes) for (int bold=0;bold<2;bold++) {
        UIFont *font=[UIFont monospacedDigitSystemFontOfSize:fs weight:bold?UIFontWeightBold:UIFontWeightRegular];
        unsigned mask=second ? ((1u<<4)|(1u<<5)|(3u<<8)|(1u<<10)) : ((1u<<0)|(1u<<2)|(1u<<10));
        SBCPUTextSlot slots[11];
        CGFloat height=SBCPUTextSlotsLayoutMemoryConfigured(mask,fs,340,0,second,
            SBCPUTextFPSConfiguredWidth(font),SBCPUTextCurrentConfiguredWidth(font),SBCPUTextMemoryConfiguredWidth(font),SBCPUTextCPUConfiguredWidth(font),slots);
        CGFloat width=1;for(int i=0;i<11;i++) width=MAX(width,slots[i].x+slots[i].width);
        SBCPUTextSlotHost *h=[[SBCPUTextSlotHost alloc] initWithFrame:CGRectMake(0,200,width,height)];[window addSubview:h];
        for(int i=0;i<11;i++) if(mask&(1u<<i)) {
            SBCPUCapsuleBackdropLabel *l=add(h,rows[i],CGRectMake(slots[i].x,slots[i].y,slots[i].width,slots[i].height));
            [l sbcpu_setTextOnlyPlainText:rows[i] font:font color:UIColor.whiteColor];l.textAlignment=SBCPUTextMetricAlignment(i);
        }
        for(int i=0;i<11;i++) {
            SBCPUTextSlot d=SBCPUTextSeparatorFrame(mask,i,second,slots);if(d.width<=0)continue;
            SBCPUCapsuleBackdropLabel *l=add(h,@"·",CGRectMake(d.x,d.y,d.width,d.height));
            [l sbcpu_setTextOnlyPlainText:@"·" font:font color:UIColor.whiteColor];
        }
        [h sbcpu_setLiveInversionRequested:YES];
        for(int sc=1;sc<=3;sc++) parity(h,sc,[NSString stringWithFormat:@"production-window%d-font%d-bold%d",second+1,fs,bold]);
        [h sbcpu_setLiveInversionRequested:NO];[h removeFromSuperview];
    }
}
static void runTests(void) {
    measurements=[NSMutableArray array]; diagnostics=[NSMutableArray array];
    syntheticCoordinates();
    UIWindow *w=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,400,400)]; w.hidden=NO;
    SBCPUTextSlotHost *a=[[SBCPUTextSlotHost alloc] initWithFrame:CGRectMake(0,0,340,64)];
    SBCPUTextSlotHost *b=[[SBCPUTextSlotHost alloc] initWithFrame:CGRectMake(0,80,340,64)];
    [w addSubview:a]; [w addSubview:b];
    SBCPUCapsuleBackdropLabel *cpu=add(a,@"CPU 25%",CGRectMake(0,0,100,19));
    add(a,@"·",CGRectMake(100,0,12,19)); add(a,@"FPS816",CGRectMake(112,0,85,19));
    SBCPUCapsuleBackdropLabel *temp=add(b,@"TEMP 42°",CGRectMake(0,0,100,19));
    add(b,@"·",CGRectMake(100,0,12,19)); add(b,@"I 278mA",CGRectMake(112,0,100,19));
    [a sbcpu_setLiveInversionRequested:YES]; [b sbcpu_setLiveInversionRequested:YES];
    for (int s=1;s<=3;s++) { parity(a,s,@"window1-CPU-FPS816"); parity(b,s,@"window2-temp-current-attachments"); }
    sync(a,3); sync(b,3); CALayer *other=[b sbcpu_testSharedBackdrop];
    SBCPUTextBackdropResetTestCounters();
    for (int i=0;i<1000;i++) { [cpu sbcpu_setTextOnlyPlainText:@"CPU 25%" font:cpu.font color:UIColor.whiteColor]; sync(a,3); sync(b,3); }
    SBCPUTextBackdropTestCounters c=SBCPUTextBackdropReadTestCounters();
    fprintf(stderr,"same-value counters: mask=%lu sharedWrites=%lu sharedCreate=%lu labelCreate=%lu\n",(unsigned long)c.maskRefreshes,(unsigned long)c.sharedMaskWrites,(unsigned long)c.sharedCreations,(unsigned long)c.backdropCreations);
    assert(c.maskRefreshes==0 && c.sharedMaskWrites==0 && c.sharedCreations==0 && c.backdropCreations==0);
    assert(c.styledAttributeBuilds==0);
    cpu.text=@"CPU 26%"; sync(a,3); assert(SBCPUTextBackdropReadTestCounters().maskRefreshes>0);
    assert(other==[b sbcpu_testSharedBackdrop]); parity(a,3,@"text-change");
    [temp sbcpu_setTextOnlyPlainText:@"TEMP 43°" font:[UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightBold] color:UIColor.whiteColor];
    parity(b,3,@"font-and-attachment-change");
    NSTextAttachment *attachment=[NSTextAttachment new]; attachment.image=[UIImage systemImageNamed:@"bolt.fill"]; attachment.bounds=CGRectMake(0,-2,10,13);
    NSMutableAttributedString *att=[[NSMutableAttributedString alloc] initWithAttributedString:temp.attributedText];
    [att addAttribute:NSAttachmentAttributeName value:attachment range:NSMakeRange(0,1)]; temp.attributedText=att;
    parity(b,3,@"attachment-image-bounds-change");
    cpu.bounds=CGRectMake(0,0,90,22); cpu.center=CGPointMake(45,11);
    parity(a,2,@"bounds-scale-change");
    cpu.center=CGPointMake(50,16); parity(a,2,@"geometry-change");
    cpu.transform=CGAffineTransformMakeScale(1.05,1); sync(a,2);
    assert(![a sbcpu_testSharedBackdrop] && cpu.realtimeInvertEnabled);
    cpu.transform=CGAffineTransformIdentity; parity(a,2,@"unsupported-transform-safe-recovery");
    a.bounds=CGRectMake(0,0,320,64); parity(a,2,@"host-bounds-change");
    cpu.hidden=YES; parity(a,2,@"slot-hidden"); cpu.hidden=NO; parity(a,2,@"slot-shown");
    a.hidden=YES; assert(![a sbcpu_testSharedBackdrop]); a.hidden=NO; parity(a,2,@"host-shown");
    [a sbcpu_setLiveInversionRequested:NO]; assert(![a sbcpu_testSharedBackdrop]);
    for (SBCPUCapsuleBackdropLabel *l in a.subviews) assert(!l.realtimeInvertEnabled);
    [a sbcpu_setLiveInversionRequested:YES]; parity(a,2,@"off-on");
    [a removeFromSuperview]; assert(![a sbcpu_testSharedBackdrop]); [w addSubview:a]; parity(a,2,@"window-reattach");
    w.hidden=YES; [a sbcpu_refreshLiveInversionVisibility]; [b sbcpu_refreshLiveInversionVisibility];
    assert(![a sbcpu_testSharedBackdrop] && ![b sbcpu_testSharedBackdrop]);
    w.hidden=NO; [a sbcpu_refreshLiveInversionVisibility]; [b sbcpu_refreshLiveInversionVisibility];
    parity(a,2,@"window-visible-again"); parity(b,3,@"window2-visible-again");
    [a sbcpu_testRejectSharedBackdrop]; assert(![a sbcpu_testSharedBackdrop]);
    for (SBCPUCapsuleBackdropLabel *l in a.subviews) {
        assert(l.realtimeInvertEnabled); NSUInteger count=0;
        for (CALayer *ch in l.layer.sublayers) if (ch.mask) count++;
        assert(count==1);
    }
    assertSingle(b); // one HUD's failure must not disable the other
    SBCPUTextSlotHost *failed=[[SBCPUTextSlotHost alloc] initWithFrame:CGRectMake(0,160,300,40)];
    [w addSubview:failed]; SBCPUCapsuleBackdropLabel *f=add(failed,@"RAM 6.1GB",CGRectMake(0,0,120,19));
    SBCPUTextBackdropFailNextSharedCreation(); [failed sbcpu_setLiveInversionRequested:YES];
    assert(![failed sbcpu_testSharedBackdrop] && f.realtimeInvertEnabled);
    [failed sbcpu_setLiveInversionRequested:NO]; assert(!f.realtimeInvertEnabled);
    productionLayout(w);
    NSDictionary *result=@{@"status":(strictFailures==0?@"PASS":@"FAIL"),@"same_value_events":@1000,@"same_value_mask_refreshes":@(c.maskRefreshes),
        @"same_value_shared_mask_writes":@(c.sharedMaskWrites),@"same_value_shared_creations":@(c.sharedCreations),
        @"same_value_perlabel_creations":@(c.backdropCreations),@"same_value_styled_attribute_builds":@(c.styledAttributeBuilds),
        @"same_value_filter_or_host_recreations":@(c.sharedCreations+c.backdropCreations),
        @"parent_coordinates":@"exact CA parent composition with independently exported native glyph pixels and real layer geometry; native renderInContext ancestry reported separately",
        @"full_host_unclipped_alpha_parity":@"exact",@"independent_mem5_union_clip_alpha_parity":@"each pixel must equal the pinned cropped mem5 value or the exact full-host mem5 value where the two differ by one alpha unit",
        @"strict_crop_failure_cases":@(strictFailures),@"mem5_quantized_crop_cases":@(quantizedCases),@"parent_shift_or_missing_controls":@(parentNegativeControls),@"diagnostics":diagnostics,@"measurements":measurements,@"mask_parity":@"exact alpha pixels and aggregate placement against pinned mem5 production renderer",
        @"boundary":@"UIKit Simulator with CALayer surrogate: no real CABackdropLayer, filter GPU performance or device compatibility proof"};
    NSString *path=NSProcessInfo.processInfo.environment[@"SBCPU_SHARED_LIVE_RESULT_PATH"];
    if (path) assert([[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:path atomically:YES]);
    puts([[result description] UTF8String]);
    assert(parentNegativeControls==6);
    assert(strictFailures==0); // diagnostic traversal never stops at first crop delta
}
int main(void) { @autoreleasepool { runTests(); } return 0; }
