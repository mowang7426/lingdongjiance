#import <UIKit/UIKit.h>
#import "../SBCPUTextMemory.h"
#import "../SBCPUTextBackdropLabel.h"
#include <assert.h>
#include <string.h>
static NSData *pixels(UILabel *label,CGFloat width,CGFloat height,CGFloat scale) {
 UIGraphicsBeginImageContextWithOptions(CGSizeMake(width,height),NO,scale);
 [label drawTextInRect:label.bounds];UIImage *image=UIGraphicsGetImageFromCurrentImageContext();
 NSData *data=CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage)));
 UIGraphicsEndImageContext();return data;
}
int main(void) { @autoreleasepool {
 uint64_t amounts[]={0,100ULL<<20,999ULL<<20,1024ULL<<20,8ULL<<30,128ULL<<30,4ULL<<40};
 unsigned checks=0;
 for(int fs=8;fs<=24;fs++) for(int bold=0;bold<2;bold++) {
  UIFont *font=[UIFont monospacedDigitSystemFontOfSize:fs weight:bold?UIFontWeightBold:UIFontWeightRegular];
  CGFloat width=SBCPUTextMemoryConfiguredWidth(font);assert(width==SBCPUTextMemoryConfiguredWidth(font));
  for(int sample=-1;sample<7;sample++) {
   SBCPUMemoryMetrics m={sample>=0,sample>=0?amounts[sample]:0,8ULL<<40,16384};
   NSString *value=SBCPUTextMemoryValue(m);assert([value hasPrefix:@"RAM"]);
   if(sample<0) assert([value isEqualToString:@"RAM--"]);
   for(int scale=1;scale<=3;scale++) {
    CGFloat w=ceil(width),h=ceil(fs*1.4),canvas=w+64;
    SBCPUCapsuleBackdropLabel *label=[[SBCPUCapsuleBackdropLabel alloc] initWithFrame:CGRectMake(0,0,w,h)];
    label.font=font;label.text=value;label.numberOfLines=1;label.lineBreakMode=NSLineBreakByClipping;
    label.textAlignment=NSTextAlignmentLeft;label.clipsToBounds=YES;label.adjustsFontSizeToFitWidth=NO;
    NSData *fixed=pixels(label,canvas,h,scale);label.bounds=CGRectMake(0,0,canvas,h);
    assert([fixed isEqualToData:pixels(label,canvas,h,scale)]);checks++;
   }
   for(int hud=0;hud<2;hud++) for(int size=0;size<3;size++) {
    double available=(double[]){125,390,844}[size];
    for(int dual=0;dual<=1;dual++) {
     unsigned old=(1u<<10)-1; SBCPUTextSlot slots[11],next[11],original[10];
     double fps=SBCPUTextFPSConfiguredWidth(font);
     double prior=SBCPUTextSlotsLayoutNetworkFPS(old,fs,available,4,dual,fps,original);
     double disabled=SBCPUTextSlotsLayoutMemory(old,fs,available,4,dual,fps,width,slots);
     assert(prior==disabled && memcmp(slots,original,sizeof(original))==0 && slots[10].width==0);
     double height=SBCPUTextSlotsLayoutMemory(old|(1u<<10),fs,available,4,dual,fps,width,slots);
     assert(height>=prior && slots[10].width>0 && slots[10].x+slots[10].width<=available);
     assert(SBCPUTextSlotsLayoutMemory(old|(1u<<10),fs,available,4,dual,fps,width,next)==height);
     assert(memcmp(slots,next,sizeof(slots))==0);
     SBCPUTextSlot dot=SBCPUTextSeparatorFrame(old|(1u<<10),10,dual,slots);
     assert(dot.width>=0);checks++;
    }
   }
  }
 }
 printf("PASS production UIKit RAM fonts/bitmap/scale/default-off/both HUDs: %u checks\n",checks);
 }return 0; }
