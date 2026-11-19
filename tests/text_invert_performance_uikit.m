// Simulator-only exercise of the production SBCPUTextBackdropLabel class.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../SBCPUTextBackdropLabel.h"
#import "../SBCPUTextOnlyTypography.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#import "text_invert_diagnostics.h"

static NSData *pixels(UIImage *image) {
    assert(image && image.CGImage);
    return CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage)));
}
static UIImage *drawLabel(UILabel *label, CGFloat scale) {
    UIGraphicsBeginImageContextWithOptions(label.bounds.size, NO, scale);
    [label drawTextInRect:label.bounds];
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
static SBCPUCapsuleBackdropLabel *makeLabel(NSString *text, UIFont *font, NSTextAlignment alignment, CGFloat width) {
    SBCPUCapsuleBackdropLabel *label=[[SBCPUCapsuleBackdropLabel alloc] initWithFrame:CGRectMake(0,0,width,ceil(font.pointSize*1.5))];
    label.backgroundColor=UIColor.clearColor;
    label.numberOfLines=1; label.lineBreakMode=NSLineBreakByClipping;
    label.adjustsFontSizeToFitWidth=NO; label.minimumScaleFactor=0.0;
    label.baselineAdjustment=UIBaselineAdjustmentAlignBaselines;
    label.semanticContentAttribute=UISemanticContentAttributeUnspecified;
    label.textAlignment=alignment; label.clipsToBounds=YES;
    [label sbcpu_setTextOnlyPlainText:text font:font color:UIColor.whiteColor];
    label.realtimeInvertEnabled=YES;
    [label layoutSubviews];
    return label;
}
#import "text_invert_mem4_comparison.h"
static unsigned gRawReferenceMismatches, gScaleOnlyMatches, gWhiteNormalizedMatches;
static void assertMaskParity(NSString *text, UIFont *font, NSTextAlignment alignment, CGFloat width, CGFloat scale) {
    SBCPUCapsuleBackdropLabel *label=makeLabel(text,font,alignment,width);
    UILabel *reference=[[UILabel alloc] initWithFrame:label.bounds];
    reference.backgroundColor=UIColor.clearColor; reference.textColor=UIColor.whiteColor;
    reference.clipsToBounds=YES; reference.layer.contentsScale=scale;
    reference.font=font; reference.text=text;
    reference.attributedText=SBCPUTextOnlyAttributedRow(text,font,UIColor.whiteColor);
    reference.numberOfLines=label.numberOfLines; reference.lineBreakMode=label.lineBreakMode;
    reference.adjustsFontSizeToFitWidth=label.adjustsFontSizeToFitWidth;
    reference.minimumScaleFactor=label.minimumScaleFactor;
    reference.baselineAdjustment=label.baselineAdjustment;
    reference.semanticContentAttribute=label.semanticContentAttribute;
    reference.textAlignment=label.textAlignment;
    UIImage *expected=drawLabel(reference,scale);
    UIImage *actual=SBCPUTextBackdropCopyMaskImageForTesting(label,scale);
    NSString *name=[NSString stringWithFormat:@"%@-%gpt-%@-align%ld-scale%g",text,font.pointSize,font.fontName,(long)alignment,scale];
    SBCPUMem4CapsuleLabel *mem4=makeMem4Label(text,font,alignment,width);
    assertMem4Pixels(label,mem4,scale,name);
    BOOL rawMatch=[pixels(actual) isEqualToData:pixels(expected)];
    if (!rawMatch) {
        // Keep the old failing reference visible, never relax pixel tolerance.
        if (gRawReferenceMismatches<12) {
            saveParityDiagnostic([@"original-reference-" stringByAppendingString:name],actual,expected,label,reference,scale);
            saveParityDiagnostic([@"mem4-vs-original-reference-" stringByAppendingString:name],mem4Mask(mem4,scale),expected,mem4,reference,scale);
        }
        gRawReferenceMismatches++;
    }
    // Export context scale is NOT UILabel's display/content scale. mem4's
    // glyph label keeps the screen scale even when exporting at 1x/2x.
    reference.contentScaleFactor=label.contentScaleFactor;
    if (!rawMatch && [pixels(actual) isEqualToData:pixels(drawLabel(reference,scale))]) gScaleOnlyMatches++;
    // A mask is opaque-white text AND attachments, unlike the raw UILabel.
    // Apply the documented mem4 mask semantics in an independent UILabel.
    // Use the SAME attributed input as the production label. Regenerating SF
    // Symbols creates a separately configured image, not an identical UILabel
    // input; retain that original comparison above as diagnostic evidence.
    NSMutableAttributedString *white=[label.attributedText mutableCopy];
    [white addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor range:NSMakeRange(0,white.length)];
    [label.attributedText enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0,reference.attributedText.length) options:0 usingBlock:^(id value,NSRange range,BOOL *stop) {
        (void)stop;if (![value isKindOfClass:NSTextAttachment.class]) return;
        NSTextAttachment *source=value,*a=[NSTextAttachment new];a.bounds=source.bounds;
        a.image=[source.image imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        [white addAttribute:NSAttachmentAttributeName value:a range:range];
    }];
    reference.attributedText=white;
    expected=drawLabel(reference,scale);
    if (!rawMatch && [pixels(actual) isEqualToData:pixels(expected)]) gWhiteNormalizedMatches++;
    if (![pixels(actual) isEqualToData:pixels(expected)]) saveParityDiagnostic([@"normalized-reference-" stringByAppendingString:name],actual,expected,label,reference,scale);
    assert(actual && [pixels(actual) isEqualToData:pixels(expected)]);
    mem4.realtimeInvertEnabled=NO;
    label.realtimeInvertEnabled=NO;
    assert(![label sbcpu_testCopyAlphaMaskAtScale:scale]);
}
static NSDictionary *gTestResult;
static void testNoOpAndDirtyRefresh(void) {
    UIFont *font=[UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightRegular];
    SBCPUCapsuleBackdropLabel *label=makeLabel(@"CPU 25%",font,NSTextAlignmentLeft,140);
    NSData *maskBefore=pixels(SBCPUTextBackdropCopyMaskImageForTesting(label,2));
    SBCPUTextBackdropResetTestCounters();
    CFTimeInterval start=CACurrentMediaTime();
    for (int i=0;i<1000;i++) {
        [label sbcpu_setTextOnlyPlainText:@"CPU 25%" font:font color:UIColor.whiteColor];
        label.font=font; label.textAlignment=NSTextAlignmentLeft;
        label.numberOfLines=1; label.lineBreakMode=NSLineBreakByClipping;
        label.adjustsFontSizeToFitWidth=NO; label.minimumScaleFactor=0.0;
        label.baselineAdjustment=UIBaselineAdjustmentAlignBaselines;
        label.semanticContentAttribute=UISemanticContentAttributeUnspecified;
        label.frame=CGRectMake(0,0,140,24);
        label.realtimeInvertEnabled=YES;
        [label layoutSubviews];
    }
    double elapsedMs=(CACurrentMediaTime()-start)*1000.0;
    SBCPUTextBackdropTestCounters c=SBCPUTextBackdropReadTestCounters();
    assert(c.syncCalls==1000 && c.cacheHits==1000);
    assert(c.maskRefreshes==0 && c.backdropCreations==0 && c.styledAttributeBuilds==0);
    assert([maskBefore isEqualToData:pixels(SBCPUTextBackdropCopyMaskImageForTesting(label,2))]);
    printf("same-state: 1000 UI event cycles, %.3f ms total (%.3f ms/cycle), mask refreshes=0, test-backdrop creations=0, attributed rows rebuilt=0\n",elapsedMs,elapsedMs/1000.0);

    gTestResult=@{@"simulator_only":@YES,@"same_state_cycles":@1000,@"elapsed_ms":@(elapsedMs),
        @"elapsed_ms_per_cycle":@(elapsedMs/1000.0),@"cache_hits":@(c.cacheHits),
        @"mask_refreshes":@(c.maskRefreshes),@"test_backdrop_creations":@(c.backdropCreations),
        @"attributed_rows_rebuilt":@(c.styledAttributeBuilds),
        @"test_backend_note":@"CALayer mask host; private CABackdropLayer/CAFilter/GPU not exercised"};

    SBCPUTextBackdropResetTestCounters();
    [label sbcpu_setTextOnlyPlainText:@"CPU 26%" font:font color:UIColor.whiteColor]; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1 && SBCPUTextBackdropReadTestCounters().styledAttributeBuilds==1);
    assert(![maskBefore isEqualToData:pixels(SBCPUTextBackdropCopyMaskImageForTesting(label,2))]);
    SBCPUTextBackdropResetTestCounters();
    UIFont *larger=[UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightBold];
    [label sbcpu_setTextOnlyPlainText:@"CPU 26%" font:larger color:UIColor.whiteColor]; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    label.textAlignment=NSTextAlignmentRight; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    label.frame=CGRectMake(0,0,112,28); [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    label.lineBreakMode=NSLineBreakByWordWrapping; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    label.lineBreakMode=NSLineBreakByClipping; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    label.numberOfLines=2; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    label.adjustsFontSizeToFitWidth=YES; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    label.minimumScaleFactor=0.8; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    label.baselineAdjustment=UIBaselineAdjustmentAlignCenters; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    label.semanticContentAttribute=UISemanticContentAttributeForceRightToLeft; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1);
    SBCPUTextBackdropResetTestCounters();
    [label sbcpu_setTextOnlyPlainText:@"CPU 26%" font:larger color:UIColor.blackColor]; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==1 && SBCPUTextBackdropReadTestCounters().styledAttributeBuilds==1);
    CGFloat activeScale=label.window.screen.scale ?: UIScreen.mainScreen.scale;
    for (int scale=1;scale<=3;scale++) {
        SBCPUTextBackdropResetTestCounters(); [label sbcpu_testSyncBackdropAtScale:scale];
        SBCPUTextBackdropTestCounters changed=SBCPUTextBackdropReadTestCounters();
        assert(changed.maskRefreshes==(scale==activeScale?0:1));
        activeScale=scale;
        SBCPUTextBackdropResetTestCounters(); [label sbcpu_testSyncBackdropAtScale:scale];
        assert(SBCPUTextBackdropReadTestCounters().maskRefreshes==0 && SBCPUTextBackdropReadTestCounters().cacheHits==1);
    }
    SBCPUTextBackdropResetTestCounters(); label.realtimeInvertEnabled=NO;
    assert(![label sbcpu_testCopyAlphaMaskAtScale:2]);
    label.realtimeInvertEnabled=YES; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().backdropCreations==1);
    label.hidden=YES; assert(!label.realtimeInvertEnabled);
    assert(![label sbcpu_testCopyAlphaMaskAtScale:2]);
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,240,100)];
    [window addSubview:label]; assert(label.window==window);
    label.hidden=NO;
    SBCPUTextBackdropResetTestCounters();
    label.realtimeInvertEnabled=YES; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().backdropCreations==1);
    [label removeFromSuperview];
    assert(!label.window && !label.realtimeInvertEnabled && ![label sbcpu_testCopyAlphaMaskAtScale:2]);
    [window addSubview:label]; assert(label.window==window && !label.realtimeInvertEnabled);
    SBCPUTextBackdropResetTestCounters();
    label.realtimeInvertEnabled=YES; [label layoutSubviews];
    assert(SBCPUTextBackdropReadTestCounters().backdropCreations==1 && [label sbcpu_testCopyAlphaMaskAtScale:2]);
}
static void assertAttachment(UILabel *label) {
    assert([label.attributedText attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL]);
}
static void testAttachmentRows(void) {
    UIFont *font=[UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightRegular];
    for (NSString *text in @[@"TEMP 42°",@"I 278mA"]) {
        SBCPUCapsuleBackdropLabel *label=makeLabel(text,font,NSTextAlignmentLeft,140);
        assertAttachment(label);
        NSData *before=pixels(SBCPUTextBackdropCopyMaskImageForTesting(label,2));
        SBCPUTextBackdropResetTestCounters();
        for (int i=0;i<1000;i++) {
            [label sbcpu_setTextOnlyPlainText:text font:font color:UIColor.whiteColor];
            [label sbcpu_applyTextOnlyColor:UIColor.whiteColor];
            label.realtimeInvertEnabled=YES;
            [label layoutSubviews];
        }
        SBCPUTextBackdropTestCounters c=SBCPUTextBackdropReadTestCounters();
        assert(c.syncCalls==1000 && c.cacheHits==1000);
        assert(c.maskRefreshes==0 && c.backdropCreations==0 && c.styledAttributeBuilds==0);
        assert([before isEqualToData:pixels(SBCPUTextBackdropCopyMaskImageForTesting(label,2))]);
        [label sbcpu_applyTextOnlyColor:UIColor.blackColor]; [label layoutSubviews];
        assertAttachment(label);
        c=SBCPUTextBackdropReadTestCounters();
        assert(c.maskRefreshes==1 && c.styledAttributeBuilds==1 && c.backdropCreations==0);
    }
    puts("PASS TEMP and current: 1000 cycles each, 1000 hits and zero mask/host/row rebuilds per row; recolor retains attachment");
    NSMutableDictionary *result=[gTestResult mutableCopy];
    result[@"attachment_same_state"] = @{@"rows":@2,@"cycles_per_row":@1000,@"hits_per_row":@1000,
        @"mask_refreshes":@0,@"test_backdrop_creations":@0,@"attributed_rows_rebuilt":@0};
    gTestResult=result;
}
static void testDualLabelParity(void) {
    UIFont *font=[UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightBold];
    UIWindow *windowA=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,240,100)];
    UIWindow *windowB=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,240,100)];
    SBCPUCapsuleBackdropLabel *a=makeLabel(@"I 278mA",font,NSTextAlignmentRight,90);
    SBCPUCapsuleBackdropLabel *b=makeLabel(@"I 278mA",font,NSTextAlignmentRight,90);
    [windowA addSubview:a]; [windowB addSubview:b]; [a layoutSubviews]; [b layoutSubviews];
    UIImage *ma=SBCPUTextBackdropCopyMaskImageForTesting(a,3);
    UIImage *mb=SBCPUTextBackdropCopyMaskImageForTesting(b,3);
    assert([pixels(ma) isEqualToData:pixels(mb)]);
    NSMutableDictionary *result=[gTestResult mutableCopy]; result[@"two_window_mask_pixels_identical"]=@YES; gTestResult=result;
    a.realtimeInvertEnabled=NO; b.realtimeInvertEnabled=NO;
    windowA.hidden=YES; windowB.hidden=YES;
}
int main(void) {@autoreleasepool {
    testNoOpAndDirtyRefresh();
    testAttachmentRows();
    testDualLabelParity();
    testMem4Events();
    NSArray *strings=@[@"CPU 100%",@"TEMP 42°",@"I 278mA",@"RAM1.00GB",@"FPS120"];
    NSArray *sizes=@[@8,@13,@18,@24]; unsigned parityCases=0;
    for (NSNumber *size in sizes) for (int bold=0;bold<2;bold++) {
        UIFont *font=[UIFont monospacedDigitSystemFontOfSize:size.doubleValue weight:bold?UIFontWeightBold:UIFontWeightRegular];
        for (NSString *text in strings) for (int align=0;align<3;align++) for (int scale=1;scale<=3;scale++) {
            assertMaskParity(text,font,(NSTextAlignment)align,MAX(48,size.doubleValue*5.5),scale); parityCases++;
        }
    }
    printf("PASS production UIKit label path: %u exact glyph-mask pixel parity cases; 8/13/18/24pt normal+bold; alignments left/center/right; scales 1x/2x/3x; attachment glyphs; dirty refresh, enable/disable, hidden cleanup, dual-label parity\n",parityCases);
    const char *resultPath=getenv("SBCPU_TEXT_INVERT_RESULT_PATH");
    if (resultPath && gTestResult) {
        NSMutableDictionary *result=[gTestResult mutableCopy]; result[@"mask_parity_cases"]=@(parityCases);
        result[@"mem4_production_exact_pixel_cases"]=@(gMem4ParityCases);
        result[@"original_independent_reference_mismatches"]=@(gRawReferenceMismatches);
        result[@"original_mismatches_resolved_by_display_scale_only"]=@(gScaleOnlyMatches);
        result[@"original_mismatches_resolved_by_mask_semantics"]=@(gWhiteNormalizedMatches);
        result[@"reference_explanation"]=@"Original UILabel forced export scale onto display scale and did not white-normalize attachment runs/images; mem4 production is the visual authority. No pixel tolerance; both pinned mem4 and normalized independent UILabel require byte equality.";
        result[@"fonts_pt"]=@[@8,@13,@18,@24]; result[@"weights"]=@[@"regular",@"bold"];
        result[@"alignments"]=@[@"left",@"center",@"right"]; result[@"scales"]=@[@1,@2,@3];
        NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        assert(json && [json writeToFile:[NSString stringWithUTF8String:resultPath] atomically:YES]);
    }
} return 0; }
