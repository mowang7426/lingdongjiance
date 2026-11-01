#ifndef SBCPU_TEXT_MEMORY_H
#define SBCPU_TEXT_MEMORY_H
#import "SBCPUTextFPSBudget.h"
#import "SBCPUMemoryMetrics.h"
static inline NSString *SBCPUTextMemoryValue(SBCPUMemoryMetrics sample) {
    if (!sample.valid) return @"RAM--";
    // Preserve the panel's used/total ABI; their exact integer difference is
    // min(HOST_VM_INFO64.free_count * host_page_size, physicalMemory).
    if (!sample.total_bytes || sample.used_bytes > sample.total_bytes) return @"RAM--";
    uint64_t freeBytes=sample.total_bytes-sample.used_bytes;
    if (freeBytes<(1ULL<<30)) return [NSString stringWithFormat:@"RAM%.0fMB",freeBytes/1048576.0];
    NSArray *units=@[@"GB",@"TB",@"PB",@"EB"];
    unsigned unit=0; uint64_t divisor=1ULL<<30;
    while (unit<3 && freeBytes>=divisor*1024ULL) { divisor*=1024ULL; unit++; }
    double value=(double)freeBytes/(double)divisor;
    return [NSString stringWithFormat:(freeBytes/divisor<10?@"RAM%.2f%@":@"RAM%.1f%@"),value,units[unit]];
}
static inline CGFloat SBCPUTextMemoryConfiguredWidth(UIFont *font) {
    static NSCache<UIFont *,NSNumber *> *cache; if (!cache) cache=[NSCache new]; NSNumber *hit=[cache objectForKey:font]; if (hit) return hit.doubleValue;
    // All 1024-based output shapes, including rounding across 999/9.99.
    CGFloat width=SBCPUTextFPSGlyphExtent(@"RAM--",font);
    for (int digit=0;digit<=9;digit++) {
        NSString *d=[NSString stringWithFormat:@"%d",digit];
        for (NSString *unit in @[@"MB",@"GB",@"TB",@"PB",@"EB"]) {
            for (int whole=1;whole<=4;whole++) {
                NSString *n=[@"" stringByPaddingToLength:whole withString:d startingAtIndex:0];
                for (NSString *suffix in @[@"",[@"." stringByAppendingString:d],[@"." stringByAppendingString:[d stringByAppendingString:d]]]) {
                    if ([unit isEqualToString:@"MB"] && suffix.length) continue;
                    if (![unit isEqualToString:@"MB"] && (suffix.length==0 || (suffix.length==3 && whole>2))) continue;
                    NSString *text=[NSString stringWithFormat:@"RAM%@%@%@",n,suffix,unit];
                    width=MAX(width,SBCPUTextFPSGlyphExtent(text,font));
                }
            }
        }
    }
    width=ceil(width)+2; [cache setObject:@(width) forKey:font]; return width;
}
static inline CGFloat SBCPUTextCurrentConfiguredWidth(UIFont *font) {
    static NSCache<UIFont *,NSNumber *> *cache; if (!cache) cache=[NSCache new];
    NSNumber *hit=[cache objectForKey:font]; if (hit) return hit.doubleValue;
    CGFloat width=SBCPUTextFPSGlyphExtent(@"--mA",font);
    // Production uses monospaced digits. Cover every digit, sign and length;
    // five-digit values can only be +/-10000. No live sample enters the cache.
    for (int digit=0;digit<=9;digit++) for (int count=1;count<=4;count++) {
        NSString *d=[NSString stringWithFormat:@"%d",digit];
        NSString *n=[@"" stringByPaddingToLength:count withString:d startingAtIndex:0];
        for (NSString *sign in @[@"",@"-"])
            width=MAX(width,SBCPUTextFPSGlyphExtent([NSString stringWithFormat:@"%@%@mA",sign,n],font));
    }
    for (NSString *edge in @[@"10000mA",@"-10000mA"])
        width=MAX(width,SBCPUTextFPSGlyphExtent(edge,font));
    width=ceil(width)+2; [cache setObject:@(width) forKey:font]; return width;
}
static inline CGFloat SBCPUTextCPUConfiguredWidth(UIFont *font) {
    static NSCache<UIFont *,NSNumber *> *cache; if (!cache) cache=[NSCache new];
    NSNumber *hit=[cache objectForKey:font]; if (hit) return hit.doubleValue;
    CGFloat width=SBCPUTextFPSGlyphExtent(@"CPU --%",font);
    // The sampler emits 0.0..100.0%. Monospaced digits allow finite templates
    // for each supported shape, measured only on a font configuration miss.
    for (int digit=0;digit<=9;digit++) {
        for (NSString *text in @[[NSString stringWithFormat:@"CPU %d.%d%%",digit,digit],
                                 [NSString stringWithFormat:@"CPU %d%d.%d%%",digit,digit,digit]])
            width=MAX(width,SBCPUTextFPSGlyphExtent(text,font));
    }
    width=MAX(width,SBCPUTextFPSGlyphExtent(@"CPU 100.0%",font));
    width=ceil(width)+2; [cache setObject:@(width) forKey:font]; return width;
}
static inline NSTextAlignment SBCPUTextMetricAlignment(int metric) {
    // Fixed frames/dots remain sample-independent. Split unavoidable short-value
    // reserve between both edges instead of moving the whole hole to one side.
    return (metric==0 || metric==5) ? NSTextAlignmentCenter : NSTextAlignmentLeft;
}
/* Keep the original ten metric identities/order; RAM remains appended as slot 10. */
static inline double SBCPUTextSlotsLayoutMemoryConfigured(unsigned mask,double font,double available,double gap,int dual,double fpsWidth,double currentWidth,double memoryWidth,double cpuWidth,SBCPUTextSlot slots[11]) {
    double height=SBCPUTextSlotsLayoutNetworkConfigured(mask&1023u,font,available,gap,dual,fpsWidth,currentWidth,cpuWidth,slots); SBCPUTextSlot empty={0,0,0,0}; slots[10]=empty; if (!(mask&(1u<<10))) return height;
    double x=0,y=0,h=font*1.4; for (int i=0;i<10;i++) if (mask&(1u<<i)) { x=slots[i].x+slots[i].width; y=slots[i].y; }
    double width=fmin(memoryWidth,fmax(0,available)); double candidate=x>0?x+SBCPUTextSeparatorWidth(font,gap):0; if (x>0 && candidate+width>available) { candidate=0; y+=h; }
    SBCPUTextSlot frame={candidate,y,width,h}; slots[10]=frame; return fmax(height,y+h);
}
static inline double SBCPUTextSlotsLayoutMemory(unsigned mask,double font,double available,double gap,int dual,double fpsWidth,double currentWidth,double memoryWidth,SBCPUTextSlot slots[11]) {
    return SBCPUTextSlotsLayoutMemoryConfigured(mask,font,available,gap,dual,fpsWidth,currentWidth,memoryWidth,0,slots);
}
#endif
