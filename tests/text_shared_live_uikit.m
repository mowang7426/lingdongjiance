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
    CGContextTranslateCTM(UIGraphicsGetCurrentContext(),offset.x,offset.y);
    CGContextClipToRect(UIGraphicsGetCurrentContext(),layer.bounds);
    [layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image;
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
    sync(h,scale); assertSingle(h);
    CALayer *b=[h sbcpu_testSharedBackdrop], *expected=[CALayer layer]; expected.frame=h.bounds;
    NSUInteger i=0; CGFloat oldBackdropArea=0;
    for (SBCPUCapsuleBackdropLabel *l in h.subviews) {
        if (l.hidden || !l.text.length || CGRectIsEmpty(l.bounds)) continue;
        oldBackdropArea+=l.bounds.size.width*l.bounds.size.height;
        SBCPUMem5CapsuleBackdropLabel *m=[[SBCPUMem5CapsuleBackdropLabel alloc] initWithFrame:l.bounds];
        m.font=l.font; m.text=l.text; m.attributedText=l.attributedText;
        m.textAlignment=l.textAlignment; m.numberOfLines=l.numberOfLines;
        m.lineBreakMode=l.lineBreakMode; m.adjustsFontSizeToFitWidth=l.adjustsFontSizeToFitWidth;
        m.minimumScaleFactor=l.minimumScaleFactor; m.baselineAdjustment=l.baselineAdjustment;
        m.semanticContentAttribute=l.semanticContentAttribute; m.clipsToBounds=l.clipsToBounds;
        m.realtimeInvertEnabled=YES; [m sbcpu_testSyncBackdropAtScale:scale];
        UIImage *im=[m sbcpu_testCopyAlphaMaskAtScale:scale]; assert(im);
        CALayer *actual=b.mask.sublayers[i++];
        UIImage *current=[l sbcpu_testCopyAlphaMaskAtScale:scale];
        assert(current && [alpha(current.CGImage) isEqual:alpha(im.CGImage)]);
        assert(CGSizeEqualToSize(actual.bounds.size,l.bounds.size));
        // Reuse the pinned mem5 native alpha layer, preserving original bounds
        // and drawInContext behavior. No bitmap scaling in either implementation.
        CALayer *e=m.layer.sublayers.firstObject.mask; assert(e);
        m.layer.sublayers.firstObject.mask=nil;
        e.frame=l.frame;
        [expected addSublayer:e]; m.realtimeInvertEnabled=NO;
    }
    UIImage *actual=render(b.mask,h.bounds.size,b.frame.origin,scale);
    UIImage *ref=render(expected,h.bounds.size,CGPointZero,scale);
    if (![alpha(actual.CGImage) isEqual:alpha(ref.CGImage)]) fprintf(stderr,"union placement mismatch: %s frame=%s\n",name.UTF8String,NSStringFromCGRect(b.frame).UTF8String);
    assert([alpha(actual.CGImage) isEqual:alpha(ref.CGImage)]);
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
    measurements=[NSMutableArray array];
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
    cpu.bounds=CGRectMake(0,0,90,22); parity(a,2,@"bounds-scale-change");
    cpu.center=CGPointMake(50,16); parity(a,2,@"geometry-change");
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
    NSDictionary *result=@{@"status":@"PASS",@"same_value_events":@1000,@"same_value_mask_refreshes":@(c.maskRefreshes),
        @"same_value_shared_mask_writes":@(c.sharedMaskWrites),@"same_value_filter_or_host_recreations":@(c.sharedCreations+c.backdropCreations),
        @"measurements":measurements,@"mask_parity":@"exact alpha pixels and aggregate placement against pinned mem5 production renderer",
        @"boundary":@"UIKit Simulator with CALayer surrogate: no real CABackdropLayer, filter GPU performance or device compatibility proof"};
    NSString *path=NSProcessInfo.processInfo.environment[@"SBCPU_SHARED_LIVE_RESULT_PATH"];
    if (path) assert([[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:path atomically:YES]);
    puts([[result description] UTF8String]);
}
int main(void) { @autoreleasepool { runTests(); } return 0; }
