// Actual iOS Simulator UIKit; not a real-device capture.
#import <UIKit/UIKit.h>
#import "../SBCPUTextMemory.h"
#import "../SBCPUTextOnlyCurrent.h"
#import "../SBCPUTextOnlyTypography.h"
#import "../SBCPUTextBackdropLabel.h"
#include <assert.h>
#include <string.h>
#include <stdlib.h>
static UIImage *render(UILabel *label, CGFloat width, CGFloat height, CGFloat scale, BOOL wide) {
    BOOL right=label.textAlignment==NSTextAlignmentRight;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width+128,height),NO,scale);
    CGContextTranslateCTM(UIGraphicsGetCurrentContext(),right&&wide?0:64,0);
    label.bounds=CGRectMake(0,0,width+(wide?64:0),height);
    [label drawTextInRect:label.bounds];
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();return image;
}
static NSData *data(UIImage *image) {return CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage)));}
static UILabel *label(NSString *text,UIFont *font,NSInteger metric,CGFloat width) {
    UILabel *l=[[SBCPUCapsuleBackdropLabel alloc] initWithFrame:CGRectMake(0,0,width,ceil(font.pointSize*1.4))];
    l.font=font;l.attributedText=SBCPUTextOnlyAttributedRow(text,font,UIColor.whiteColor);
    l.textAlignment=SBCPUTextMetricAlignment((int)metric);l.numberOfLines=1;
    l.lineBreakMode=NSLineBreakByClipping;l.adjustsFontSizeToFitWidth=NO;l.clipsToBounds=YES;return l;
}
static void bitmap(NSString *text,UIFont *font,int metric,CGFloat width,int scale) {
    UILabel *l=label(text,font,metric,width);CGFloat h=ceil(font.pointSize*1.4);
    NSData *fixed=data(render(l,width,h,scale,NO));
    assert([fixed isEqualToData:data(render(l,width,h,scale,YES))]);
    // Same public UILabel path used by production alpha-mask renderer.
    UILabel *mask=[[UILabel alloc] initWithFrame:CGRectMake(0,0,width,h)];
    mask.font=l.font;mask.attributedText=l.attributedText;mask.textAlignment=l.textAlignment;
    mask.numberOfLines=1;mask.lineBreakMode=l.lineBreakMode;mask.adjustsFontSizeToFitWidth=NO;
    assert([fixed isEqualToData:data(render(mask,width,h,scale,NO))]);
}
static CGFloat rightInk(UILabel *l,CGFloat width,int scale) {
    UIImage *image=render(l,width,ceil(l.font.pointSize*1.4),scale,NO);
    size_t w=CGImageGetWidth(image.CGImage),h=CGImageGetHeight(image.CGImage);
    unsigned char *p=(unsigned char *)calloc(w*h,4);assert(p);
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(p,w,h,8,w*4,cs,kCGImageAlphaPremultipliedLast);assert(c);
    CGContextDrawImage(c,CGRectMake(0,0,w,h),image.CGImage);
    NSInteger last=-1;for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++)if(p[(y*w+x)*4+3])last=MAX(last,(NSInteger)x);
    CGContextRelease(c);CGColorSpaceRelease(cs);free(p);assert(last>=0);return (last+1.0)/scale-64;
}
static SBCPUMemoryMetrics sample(uint64_t free) {
    SBCPUMemoryMetrics m={true,UINT64_MAX-free,UINT64_MAX,16384};return m;
}
static void preview(void) {
    const char *path=getenv("SBCPU_PREVIEW_PATH");if(!path)return;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(650,270),YES,2);
    [UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,650,270));
    UIFont *f=[UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightBold];
    [@"UIKit simulator fixture — NOT device screenshot" drawAtPoint:CGPointMake(16,12) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:17],NSForegroundColorAttributeName:UIColor.whiteColor}];
    NSArray *currents=@[@"278mA",@"-10000mA",@"--mA"];
    for(int row=0;row<3;row++){
        SBCPUTextSlot slots[11];unsigned mask=(1u<<0)|(1u<<5)|(1u<<10);
        SBCPUTextSlotsLayoutMemory(mask,18,630,4,0,SBCPUTextFPSConfiguredWidth(f),SBCPUTextCurrentConfiguredWidth(f),SBCPUTextMemoryConfiguredWidth(f),slots);
        NSArray *texts=@[@"CPU 25%",currents[row],@"RAM256MB"];int metrics[]={0,5,10};
        for(int k=0;k<3;k++){int i=metrics[k];UILabel *l=label(texts[k],f,i,slots[i].width);
            CGContextSaveGState(UIGraphicsGetCurrentContext());CGContextTranslateCTM(UIGraphicsGetCurrentContext(),16+slots[i].x,60+row*60);[l drawTextInRect:l.bounds];CGContextRestoreGState(UIGraphicsGetCurrentContext());
            SBCPUTextSlot d=SBCPUTextSeparatorFrame(mask,i,0,slots);if(d.width){UILabel *dot=label(@"·",f,-1,d.width);dot.textAlignment=NSTextAlignmentCenter;
                CGContextSaveGState(UIGraphicsGetCurrentContext());CGContextTranslateCTM(UIGraphicsGetCurrentContext(),16+d.x,60+row*60);[dot drawTextInRect:dot.bounds];CGContextRestoreGState(UIGraphicsGetCurrentContext());}
        }
    }
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
    assert([UIImagePNGRepresentation(image) writeToFile:[NSString stringWithUTF8String:path] atomically:YES]);
}
int main(void) {@autoreleasepool {
    uint64_t amounts[]={0,256ULL<<20,999ULL<<20,(1ULL<<30)-1,1ULL<<30,1280ULL<<20,10ULL<<30,1023ULL<<30,(1ULL<<40)-1,1ULL<<40,(1ULL<<50)-1,1ULL<<50,(1ULL<<60)-1,1ULL<<60,UINT64_MAX};
    NSArray *expected=@[@"RAM0MB",@"RAM256MB",@"RAM999MB",@"RAM1024MB",@"RAM1.00GB",@"RAM1.25GB",@"RAM10.0GB",@"RAM1023.0GB",@"RAM1024.0GB",@"RAM1.00TB",@"RAM1024.0TB",@"RAM1.00PB",@"RAM1024.0PB",@"RAM1.00EB",@"RAM16.0EB"];
    for(unsigned j=0;j<sizeof(amounts)/sizeof(amounts[0]);j++)assert([SBCPUTextMemoryValue(sample(amounts[j])) isEqualToString:expected[j]]);
    SBCPUMemoryMetrics invalid={false,0,0,0},bad={true,2,1,4096};
    assert([SBCPUTextMemoryValue(invalid) isEqualToString:@"RAM--"]);assert([SBCPUTextMemoryValue(bad) isEqualToString:@"RAM--"]);
    unsigned checks=0,domain=0;
    for(int fs=8;fs<=24;fs++)for(int bold=0;bold<2;bold++){@autoreleasepool{
        UIFont *font=[UIFont monospacedDigitSystemFontOfSize:fs weight:bold?UIFontWeightBold:UIFontWeightRegular];
        CGFloat ram=SBCPUTextMemoryConfiguredWidth(font),cur=SBCPUTextCurrentConfiguredWidth(font),fps=SBCPUTextFPSConfiguredWidth(font);
        assert(ram==SBCPUTextMemoryConfiguredWidth(font)&&cur==SBCPUTextCurrentConfiguredWidth(font));
        for(int n=-10000;n<=10000;n++){@autoreleasepool{NSString *v=SBCPUTextOnlyCurrentText(@(n),1,2);assert(SBCPUTextFPSGlyphExtent(v,font)+1<=cur);domain++;}}
        NSMutableArray *values=[NSMutableArray arrayWithObject:@"RAM--"];for(NSString *v in expected)[values addObject:v];
        for(NSString *v in values)for(int scale=1;scale<=3;scale++){bitmap(v,font,10,ram,scale);checks++;}
        for(NSString *v in @[@"278mA",@"-278mA",@"0mA",@"-0mA",@"1mA",@"9999mA",@"-9999mA",@"10000mA",@"-10000mA",@"--mA"])for(int scale=1;scale<=3;scale++){bitmap(v,font,5,cur,scale);checks++;}
        for(int scale=1;scale<=3;scale++){
            CGFloat edge=rightInk(label(@"278mA",font,5,cur),cur,scale);
            for(NSString *v in @[@"-10000mA",@"10000mA",@"0mA",@"--mA"])
                assert(fabs(edge-rightInk(label(v,font,5,cur),cur,scale))<=1.0/scale+0.01);
            CGFloat oldWidth=9*fs*.65;UILabel *old=label(@"278mA",font,-1,oldWidth);
            CGFloat oldTail=oldWidth-rightInk(old,oldWidth,scale),newTail=cur-edge;
            CGFloat cpuWidth=SBCPUTextSlotWidth(0,fs,1000);
            CGFloat cpuTail=cpuWidth-rightInk(label(@"CPU 100%",font,0,cpuWidth),cpuWidth,scale);
            assert(newTail<oldTail && newTail<=cpuTail+2 && newTail>=-1);
            if(fs==13&&bold&&scale==3)printf("mem3 measured trailing ink padding: old278=%.3f new278=%.3f CPU100=%.3f; common dot slot=%.3f\n",(double)oldTail,(double)newTail,(double)cpuTail,SBCPUTextSeparatorWidth(fs,4));
        }
        for(int hud=0;hud<2;hud++)for(int dual=0;dual<2;dual++)for(int gap=-15;gap<=12;gap++){
            for(int screen=0;screen<3;screen++){double available=(double[]){180,390,844}[screen];
                SBCPUTextSlot a[11],b[11],old[10];unsigned mask=2047;
                double h=SBCPUTextSlotsLayoutMemory(mask,fs,available,gap,hud&&dual,fps,cur,ram,a);
                assert(SBCPUTextSlotsLayoutMemory(mask,fs,available,gap,hud&&dual,fps,cur,ram,b)==h&&memcmp(a,b,sizeof(a))==0);
                double prior=SBCPUTextSlotsLayoutNetworkFPSCurrent(1023,fs,available,gap,hud&&dual,fps,cur,old);
                assert(SBCPUTextSlotsLayoutMemory(1023,fs,available,gap,hud&&dual,fps,cur,ram,b)==prior&&memcmp(b,old,sizeof(old))==0&&b[10].width==0);
                assert(a[5].width==cur&&a[10].width==ram);
                for(int i=0;i<11;i++){SBCPUTextSlot d=SBCPUTextSeparatorFrame(mask,i,hud&&dual,a);if(d.width)assert(fabs(d.width-SBCPUTextSeparatorWidth(fs,gap))<1e-6);}
                checks++;
            }
            // Same separator allocation after CPU, current and before RAM.
            SBCPUTextSlot a[11];unsigned mask=(1u<<0)|(1u<<5)|(1u<<10);
            SBCPUTextSlotsLayoutMemory(mask,fs,1000,gap,0,fps,cur,ram,a);
            SBCPUTextSlot dc=SBCPUTextSeparatorFrame(mask,5,0,a),dr=SBCPUTextSeparatorFrame(mask,10,0,a);
            assert(fabs(dc.width-dr.width)<1e-6&&dr.x==a[5].x+cur);
        }
        printf("mem3 UIKit fs=%d bold=%d oldCurrent=%.3f current=%.3f RAM=%.3f gap=%.3f right-aligned mA fixed edge\n",fs,bold,9*fs*.65,(double)cur,(double)ram,SBCPUTextSeparatorWidth(fs,4));
    }}
    preview();printf("PASS mem3 production UIKit %u bitmap/layout checks; %u exhaustive current glyph cases; 8..24 regular/bold 1..3x; free-only thresholds, old keys, fixed dots, alpha-mask parity\n",checks,domain);
}return 0;}
