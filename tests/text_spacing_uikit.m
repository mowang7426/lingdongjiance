// iOS Simulator, fixed test data: NOT a device screenshot.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../SBCPUTextMemory.h"
#import "../SBCPUTextOnlyTypography.h"
#import "../SBCPUTextBackdropLabel.h"
#include <assert.h>
#include <string.h>
#include <stdlib.h>

static UILabel *SBCPUTestLabel(NSString *text,UIFont *font,int metric,CGFloat width,int option) {
    UILabel *l=[[SBCPUCapsuleBackdropLabel alloc] initWithFrame:CGRectMake(0,0,width,font.pointSize*1.4)];
    l.font=font;l.text=text;l.attributedText=SBCPUTextOnlyAttributedRow(text,font,UIColor.whiteColor);
    l.numberOfLines=1;l.adjustsFontSizeToFitWidth=NO;l.lineBreakMode=NSLineBreakByClipping;l.clipsToBounds=YES;
    l.textAlignment=metric<0?NSTextAlignmentCenter:SBCPUTextMetricAlignment(metric);
    if(metric==0||metric==5) {
        if(option==0)l.textAlignment=metric==5?NSTextAlignmentRight:NSTextAlignmentLeft;
        if(option==1)l.textAlignment=NSTextAlignmentLeft;
        if(option==2)l.textAlignment=NSTextAlignmentRight;
    }
    return l;
}
static UIImage *SBCPUTestRender(UILabel *l,int scale,BOOL wide,BOOL mask) {
    CGFloat width=l.bounds.size.width,height=ceil(l.bounds.size.height);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(ceil(width)+128,height),NO,scale);
    CGFloat shift=wide?(l.textAlignment==NSTextAlignmentRight?64:l.textAlignment==NSTextAlignmentCenter?32:0):0;
    CGContextTranslateCTM(UIGraphicsGetCurrentContext(),64-shift,0);
    CGRect bounds=CGRectMake(0,0,width+(wide?64:0),l.bounds.size.height);
    if(mask) {
        // Execute the actual production SBCPUTextAlphaMask drawInContext path,
        // independent of private CABackdropLayer availability in Simulator.
        CALayer *alpha=[NSClassFromString(@"SBCPUTextAlphaMask") layer];assert(alpha);
        UILabel *glyph=[[UILabel alloc] initWithFrame:bounds];glyph.font=l.font;glyph.text=l.text;
        glyph.attributedText=l.attributedText;glyph.textAlignment=l.textAlignment;
        glyph.numberOfLines=1;glyph.adjustsFontSizeToFitWidth=NO;glyph.lineBreakMode=l.lineBreakMode;
        alpha.bounds=bounds;[alpha setValue:glyph forKey:@"glyphLabel"];
        [alpha drawInContext:UIGraphicsGetCurrentContext()];
    } else {
        l.bounds=bounds;[l drawTextInRect:bounds];l.bounds=CGRectMake(0,0,width,bounds.size.height);
    }
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();return image;
}
static NSData *SBCPUTestData(UIImage *image) {return CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage)));}
static CGRect SBCPUTestInk(UILabel *l,int scale) {
    UIImage *image=SBCPUTestRender(l,scale,NO,NO);size_t w=CGImageGetWidth(image.CGImage),h=CGImageGetHeight(image.CGImage);
    unsigned char *p=(unsigned char *)calloc(w*h,4);assert(p);CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(p,w,h,8,w*4,cs,kCGImageAlphaPremultipliedLast);assert(c);
    CGContextDrawImage(c,CGRectMake(0,0,w,h),image.CGImage);NSInteger lo=(NSInteger)w,hi=-1;
    for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++)if(p[(y*w+x)*4+3]){lo=MIN(lo,(NSInteger)x);hi=MAX(hi,(NSInteger)x);}
    CGContextRelease(c);CGColorSpaceRelease(cs);free(p);assert(hi>=lo);
    return CGRectMake((double)lo/scale-64,0,(hi+1.0-lo)/scale,0);
}
static void SBCPUTestPixels(NSString *text,UIFont *font,int metric,CGFloat width,int scale) {
    UILabel *l=SBCPUTestLabel(text,font,metric,width,3);
    NSData *fixed=SBCPUTestData(SBCPUTestRender(l,scale,NO,NO));
    assert([fixed isEqualToData:SBCPUTestData(SBCPUTestRender(l,scale,YES,NO))]);
    assert([fixed isEqualToData:SBCPUTestData(SBCPUTestRender(l,scale,NO,YES))]);
    CGRect ink=SBCPUTestInk(l,scale);assert(ink.origin.x>=-1.0/scale&&CGRectGetMaxX(ink)<=width+1.0/scale);
}
static double SBCPUTestFrames(UIFont *f,int option,int dual,double available,double gap,unsigned mask,SBCPUTextSlot a[11]) {
    return SBCPUTextSlotsLayoutMemoryConfigured(mask,f.pointSize,available,gap,dual,
        SBCPUTextFPSConfiguredWidth(f),SBCPUTextCurrentConfiguredWidth(f),SBCPUTextMemoryConfiguredWidth(f),
        option?SBCPUTextCPUConfiguredWidth(f):0,a);
}
static NSDictionary *SBCPUTestGaps(UIFont *f,int option,int scale) {
    unsigned mask=1079;SBCPUTextSlot a[11];SBCPUTestFrames(f,option,0,1000,4,mask,a);
    CGRect cpu=SBCPUTestInk(SBCPUTestLabel(@"CPU 9.0%",f,0,a[0].width,option),scale);
    CGRect cur=SBCPUTestInk(SBCPUTestLabel(@"-62mA",f,5,a[5].width,option),scale);
    SBCPUTextSlot d1=SBCPUTextSeparatorFrame(mask,1,0,a),d5=SBCPUTextSeparatorFrame(mask,5,0,a),d10=SBCPUTextSeparatorFrame(mask,10,0,a);
    CGRect dot=SBCPUTestInk(SBCPUTestLabel(@"·",f,-1,d1.width,option),scale);
    double cpuRight=d1.x+dot.origin.x-(a[0].x+CGRectGetMaxX(cpu));
    double curLeft=a[5].x+cur.origin.x-(d5.x+CGRectGetMaxX(dot));
    double curRight=d10.x+dot.origin.x-(a[5].x+CGRectGetMaxX(cur));
    return @{@"cpu_width_pt":@(a[0].width),@"current_width_pt":@(a[5].width),
        @"cpu_leading_padding_pt":@(cpu.origin.x),@"cpu_to_dot_pt":@(cpuRight),
        @"dot_to_current_pt":@(curLeft),@"current_to_dot_pt":@(curRight),
        @"separator_width_pt":@(d1.width),@"row_width_pt":@(a[10].x+a[10].width),
        @"worst_pt":@(MAX(MAX(cpuRight,cpu.origin.x),MAX(curLeft,curRight)))};
}
static void SBCPUTestPreview(NSString *directory) {
    NSArray *names=@[@"BEFORE mem3: estimated CPU / right current",@"Candidate A: measured widths / left",@"Candidate B: measured widths / right",@"AFTER mem4: measured widths / centered CPU + current"];
    UIFont *font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    NSMutableArray *report=[NSMutableArray array];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(650,355),YES,3);
    [[UIColor colorWithWhite:.08 alpha:1] setFill];UIRectFill(CGRectMake(0,0,650,355));
    NSDictionary *caption=@{NSFontAttributeName:[UIFont systemFontOfSize:13],NSForegroundColorAttributeName:UIColor.whiteColor};
    [@"UIKit SIMULATOR — FIXED TEST DATA — NOT a real-device capture" drawAtPoint:CGPointMake(14,10) withAttributes:caption];
    for(int option=0;option<4;option++){
        CGFloat y=42+option*77;[names[option] drawAtPoint:CGPointMake(14,y) withAttributes:caption];
        SBCPUTextSlot a[11];unsigned mask=1079;SBCPUTestFrames(font,option,0,1000,4,mask,a);
        int ids[]={0,1,2,4,5,10};NSArray *texts=@[@"CPU 9.0%",@"2242MHz",@"FPS60",@"32.9°C",@"-62mA",@"RAM231MB"];
        for(int k=0;k<6;k++){int i=ids[k];UILabel *l=SBCPUTestLabel(texts[k],font,i,a[i].width,option);
            CGContextSaveGState(UIGraphicsGetCurrentContext());CGContextTranslateCTM(UIGraphicsGetCurrentContext(),14+a[i].x,y+25);[l drawTextInRect:l.bounds];CGContextRestoreGState(UIGraphicsGetCurrentContext());
            SBCPUTextSlot d=SBCPUTextSeparatorFrame(mask,i,0,a);if(d.width){UILabel *dot=SBCPUTestLabel(@"·",font,-1,d.width,option);
                CGContextSaveGState(UIGraphicsGetCurrentContext());CGContextTranslateCTM(UIGraphicsGetCurrentContext(),14+d.x,y+25);[dot drawTextInRect:dot.bounds];CGContextRestoreGState(UIGraphicsGetCurrentContext());}
        }
        NSMutableDictionary *record=[SBCPUTestGaps(font,option,3) mutableCopy];record[@"option"]=names[option];[report addObject:record];
        NSString *summary=[NSString stringWithFormat:@"CPU→dot %.2f pt | dot→mA %.2f pt | mA→dot %.2f pt",[record[@"cpu_to_dot_pt"] doubleValue],[record[@"dot_to_current_pt"] doubleValue],[record[@"current_to_dot_pt"] doubleValue]];
        [summary drawAtPoint:CGPointMake(14,y+48) withAttributes:caption];
    }
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
    assert([UIImagePNGRepresentation(image) writeToFile:[directory stringByAppendingPathComponent:@"mem4-before-after-uikit.png"] atomically:YES]);
    NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"source":@"iOS Simulator fixed fixture, 13pt bold 3x, dataGap=4; not inferred device settings",@"schemes":report} options:NSJSONWritingPrettyPrinted error:nil];
    assert([json writeToFile:[directory stringByAppendingPathComponent:@"mem4-spacing-measurements.json"] atomically:YES]);
    printf("MEASUREMENTS %s\n",[[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
}
int main(void) {@autoreleasepool{
    unsigned bitmaps=0,layouts=0;
    for(int fs=8;fs<=24;fs++)for(int bold=0;bold<2;bold++){@autoreleasepool{
        UIFont *f=[UIFont monospacedDigitSystemFontOfSize:fs weight:bold?UIFontWeightBold:UIFontWeightRegular];
        CGFloat cpu=SBCPUTextCPUConfiguredWidth(f),cur=SBCPUTextCurrentConfiguredWidth(f);
        assert(cpu==SBCPUTextCPUConfiguredWidth(f));
        for(int n=0;n<=1000;n++)assert(SBCPUTextFPSGlyphExtent([NSString stringWithFormat:@"CPU %.1f%%",n/10.0],f)+1<=cpu);
        for(int scale=1;scale<=3;scale++){
            for(NSString *s in @[@"CPU 0%",@"CPU 9%",@"CPU 99%",@"CPU 100%",@"CPU 0.0%",@"CPU 9.0%",@"CPU 99.9%",@"CPU 100.0%",@"CPU --%"]){SBCPUTestPixels(s,f,0,cpu,scale);bitmaps++;}
            for(NSString *s in @[@"0mA",@"-0mA",@"62mA",@"-62mA",@"278mA",@"-278mA",@"999mA",@"-999mA",@"9999mA",@"-9999mA",@"10000mA",@"-10000mA",@"--mA"]){SBCPUTestPixels(s,f,5,cur,scale);bitmaps++;}
            for(NSString *s in @[@"RAM0MB",@"RAM231MB",@"RAM1024MB",@"RAM1.00GB",@"RAM1024.0GB",@"RAM16.0EB",@"RAM--"]){SBCPUTestPixels(s,f,10,SBCPUTextMemoryConfiguredWidth(f),scale);bitmaps++;}
            SBCPUTestPixels(@"FPS816",f,2,SBCPUTextFPSConfiguredWidth(f),scale);bitmaps++;
            NSDictionary *old=SBCPUTestGaps(f,0,scale),*now=SBCPUTestGaps(f,3,scale);
            assert([now[@"cpu_to_dot_pt"] doubleValue]<[old[@"cpu_to_dot_pt"] doubleValue]);
            assert([now[@"dot_to_current_pt"] doubleValue]<[old[@"dot_to_current_pt"] doubleValue]);
            assert([now[@"current_to_dot_pt"] doubleValue]<[old[@"dot_to_current_pt"] doubleValue]);
            assert(fabs([now[@"dot_to_current_pt"] doubleValue]-[now[@"current_to_dot_pt"] doubleValue])<=2.0+2.0/scale);
            for(int option=1;option<3;option++)assert([now[@"worst_pt"] doubleValue]<=[SBCPUTestGaps(f,option,scale)[@"worst_pt"] doubleValue]+1.0/scale);
        }
        for(int hud=0;hud<2;hud++)for(int dual=0;dual<2;dual++)for(int gap=-15;gap<=12;gap++)for(int screen=0;screen<3;screen++){
            double available=(double[]){180,390,844}[screen];SBCPUTextSlot a[11],b[11];
            double h=SBCPUTestFrames(f,3,hud&&dual,available,gap,2047,a);
            assert(h==SBCPUTestFrames(f,3,hud&&dual,available,gap,2047,b)&&memcmp(a,b,sizeof(a))==0);
            assert(a[0].width==cpu&&a[5].width==cur);
            for(int i=0;i<11;i++){assert(a[i].x>=0&&a[i].x+a[i].width<=available+1e-6);SBCPUTextSlot d=SBCPUTextSeparatorFrame(2047,i,hud&&dual,a);if(d.width)assert(fabs(d.width-SBCPUTextSeparatorWidth(fs,gap))<1e-6);}
            layouts++;
        }
    }}
    const char *path=getenv("SBCPU_SPACING_OUTPUT");assert(path);SBCPUTestPreview([NSString stringWithUTF8String:path]);
    printf("PASS mem4 %u real UIKit bitmap+production alpha-mask cases; %u two-HUD layouts; CPU domain 0.0..100.0; fonts 8..24 regular/bold scales 1..3; four alignment options; no clipping, stable frames/dots\n",bitmaps,layouts);
}return 0;}
