#import "SBCPUMem4BackdropLabel.h"
static unsigned gMem4ParityCases;
static UIImage *mem4Mask(SBCPUMem4BackdropLabel *label, CGFloat scale) {
    CALayer *mask=label.layer.sublayers.lastObject.mask;
    assert(mask && !CGRectIsEmpty(mask.bounds));
    UIGraphicsBeginImageContextWithOptions(mask.bounds.size,NO,scale);
    [mask drawInContext:UIGraphicsGetCurrentContext()];
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();return image;
}
static SBCPUMem4CapsuleLabel *makeMem4Label(NSString *text,UIFont *font,NSTextAlignment alignment,CGFloat width) {
    SBCPUMem4CapsuleLabel *l=[[SBCPUMem4CapsuleLabel alloc] initWithFrame:CGRectMake(0,0,width,ceil(font.pointSize*1.5))];
    l.backgroundColor=UIColor.clearColor;
    l.numberOfLines=1;l.lineBreakMode=NSLineBreakByClipping;
    l.adjustsFontSizeToFitWidth=NO;l.minimumScaleFactor=0;
    l.baselineAdjustment=UIBaselineAdjustmentAlignBaselines;
    l.semanticContentAttribute=UISemanticContentAttributeUnspecified;
    l.textAlignment=alignment;l.clipsToBounds=YES;
    l.text=text;l.font=font;l.textColor=UIColor.whiteColor;
    l.attributedText=SBCPUTextOnlyAttributedRow(text,font,UIColor.whiteColor);
    l.realtimeInvertEnabled=YES;[l layoutSubviews];return l;
}
static void assertMem4Pixels(SBCPUCapsuleBackdropLabel *now,SBCPUMem4CapsuleLabel *old,CGFloat scale,NSString *name) {
    UIImage *actual=SBCPUTextBackdropCopyMaskImageForTesting(now,scale),*expected=mem4Mask(old,scale);
    if (![pixels(actual) isEqualToData:pixels(expected)]) saveParityDiagnostic([@"mem4-" stringByAppendingString:name],actual,expected,now,old,scale);
    assert([pixels(actual) isEqualToData:pixels(expected)]);gMem4ParityCases++;
}
static void testMem4Events(void) {
    UIFont *font=[UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightRegular];
    for (NSString *initial in @[@"CPU 25%",@"TEMP 42°",@"I 278mA"]) {
        SBCPUCapsuleBackdropLabel *now=makeLabel(initial,font,NSTextAlignmentLeft,140);
        SBCPUMem4CapsuleLabel *old=makeMem4Label(initial,font,NSTextAlignmentLeft,140);
        for (int event=0;event<30;event++) {
            NSString *text=event<10?initial:event<20?@"CPU 26%":@"TEMP 44°";
            UIFont *f=event<15?font:[UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightBold];
            UIColor *color=event<25?UIColor.whiteColor:UIColor.blackColor;
            // The same original HUD event: metric text/font/color, attributed row,
            // typography and frame then enabled/layout. mem5 coalesces equal inputs.
            [now sbcpu_setTextOnlyPlainText:text font:f color:color];
            old.text=text;old.font=f;old.textColor=color;
            old.attributedText=SBCPUTextOnlyAttributedRow(text,f,color);
            NSTextAlignment a=event<18?NSTextAlignmentLeft:event<24?NSTextAlignmentCenter:NSTextAlignmentRight;
            now.textAlignment=a;old.textAlignment=a;
            CGRect frame=CGRectMake(0,0,event<22?140:112,event<22?24:28);
            now.frame=frame;old.frame=frame;
            now.realtimeInvertEnabled=YES;old.realtimeInvertEnabled=YES;
            [now layoutSubviews];[old layoutSubviews];
            for (int scale=1;scale<=3;scale++) assertMem4Pixels(now,old,scale,[NSString stringWithFormat:@"%@-event%d-scale%d",initial,event,scale]);
        }
    }
}
