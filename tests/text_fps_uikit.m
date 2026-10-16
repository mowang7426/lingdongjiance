// Executed against iOS Simulator UIKit, NOT an AppKit font approximation.
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import "../SBCPUTextFPSBudget.h"
#import "../SBCPUTextOnlyTypography.h"
#import "../SBCPUTextBackdropLabel.h"
#include <assert.h>
#include <string.h>

static NSData *pixels(UILabel *label, CGFloat width, CGFloat height, CGFloat scale) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width,height),NO,scale);
    [label drawTextInRect:label.bounds];
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();
    NSData *data=CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage)));
    UIGraphicsEndImageContext();
    return data;
}
int main(void) {
 @autoreleasepool {
    NSArray<NSString *> *values=@[@"FPS0",@"FPS60",@"FPS99",@"FPS100",@"FPS120",@"FPS240",@"FPS999",@"FPS--"];
    unsigned comparisons=0,oldOverflows=0;
    for (int fs=8;fs<=24;fs++) for (int bold=0;bold<2;bold++) {
        UIFont *font=[UIFont monospacedDigitSystemFontOfSize:fs weight:bold?UIFontWeightBold:UIFontWeightRegular];
        CGFloat budget=SBCPUTextFPSConfiguredWidth(font);
        assert(budget==SBCPUTextFPSConfiguredWidth(font));
        CGFloat worst=0;
        for (int n=0;n<1000;n++) {
            CGFloat extent=SBCPUTextFPSGlyphExtent([NSString stringWithFormat:@"FPS%d",n],font);
            assert(extent+2<=budget+1e-6); worst=MAX(worst,extent);
        }
        if (worst>6*fs*.65) oldOverflows++;
        printf("UIKit fs=%d bold=%d font=%s old=%.3f glyphWorst=%.3f reserved=%.3f oldOverflow=%d\n",
            fs,bold,font.fontName.UTF8String,6*fs*.65,(double)worst,(double)budget,worst>6*fs*.65);
        for (NSString *value in values) {
            assert([value hasPrefix:@"FPS"] && ![value containsString:@" "]);
            NSAttributedString *text=SBCPUTextOnlyAttributedRow(value,font,UIColor.whiteColor);
            assert([text.string isEqualToString:value]);
            for (int scale=1;scale<=3;scale++) {
                CGFloat w=ceil(budget),h=ceil(fs*1.4),canvas=w+64;
                // Real production label, with all clipping/line-break settings.
                SBCPUCapsuleBackdropLabel *label=[[SBCPUCapsuleBackdropLabel alloc] initWithFrame:CGRectMake(0,0,w,h)];
                label.font=font; label.attributedText=text; label.numberOfLines=1;
                label.lineBreakMode=NSLineBreakByClipping; label.textAlignment=NSTextAlignmentLeft;
                label.adjustsFontSizeToFitWidth=NO; label.clipsToBounds=YES;
                NSData *fixed=pixels(label,canvas,h,scale);
                label.bounds=CGRectMake(0,0,canvas,h);
                NSData *unclipped=pixels(label,canvas,h,scale);
                assert([fixed isEqualToData:unclipped]);
                // The alpha mask uses a matching white UILabel, same bounds
                // and attributes. This checks public glyph path parity; it
                // does NOT claim to test real-device CABackdropLayer compositing.
                UILabel *glyph=[[UILabel alloc] initWithFrame:CGRectMake(0,0,w,h)];
                glyph.font=font; glyph.attributedText=text; glyph.numberOfLines=1;
                glyph.lineBreakMode=NSLineBreakByClipping; glyph.textAlignment=NSTextAlignmentLeft;
                glyph.adjustsFontSizeToFitWidth=NO;
                assert([fixed isEqualToData:pixels(glyph,canvas,h,scale)]);
                comparisons++;
            }
            // Same width for both HUDs, all configured gaps and network modes.
            for (int hud=0;hud<2;hud++) for (int gap=-15;gap<=12;gap++) {
                SBCPUTextSlot a[10],b[10];
                double height=SBCPUTextSlotsLayoutNetworkFPS(1023,fs,390,gap,hud,budget,a);
                assert(SBCPUTextSlotsLayoutNetworkFPS(1023,fs,390,gap,hud,budget,b)==height);
                assert(memcmp(a,b,sizeof(a))==0);
                assert(a[2].width==budget);
                for (int i=0;i<10;i++) {
                    SBCPUTextSlot dot=SBCPUTextSeparatorFrame(1023,i,hud,a);
                    SBCPUTextSlot next=SBCPUTextSeparatorFrame(1023,i,hud,b);
                    assert(memcmp(&dot,&next,sizeof(dot))==0);
                    if (dot.width) {
                        assert(fabs(dot.width-SBCPUTextSeparatorWidth(fs,gap))<1e-6);
                        assert(fabs(dot.x+dot.width-a[i].x)<1e-6);
                    }
                    if (i!=2) assert(a[i].width==SBCPUTextSlotWidth(i,fs,390));
                }
            }
        }
    }
    printf("PASS UIKit actual glyphs + bitmap/no clipping: %u comparisons; historical overflow configurations=%u; sizes 8..24 regular/bold, scales 1/2/3, both HUDs and gaps -15..12\n",comparisons,oldOverflows);
 }
 return 0;
}
