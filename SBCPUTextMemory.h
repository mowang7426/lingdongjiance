#ifndef SBCPU_TEXT_MEMORY_H
#define SBCPU_TEXT_MEMORY_H
#import "SBCPUTextFPSBudget.h"
#import "SBCPUMemoryMetrics.h"
static inline NSString *SBCPUTextMemoryValue(SBCPUMemoryMetrics sample) {
    if (!sample.valid) return @"RAM--";
    double value=sample.available_bytes/1048576.0;
    if (value<1024) return [NSString stringWithFormat:@"RAM%.0fMB",value];
    NSArray *units=@[@"GB",@"TB",@"PB",@"EB"];
    for (NSString *unit in units) {
        value/=1024;
        if (value<1024 || [unit isEqualToString:@"EB"])
            return [NSString stringWithFormat:@"RAM%.1f%@",value,unit];
    }
    return @"RAM--";
}
static inline CGFloat SBCPUTextMemoryConfiguredWidth(UIFont *font) {
    static NSCache<UIFont *,NSNumber *> *cache;
    if (!cache) cache=[NSCache new];
    NSNumber *hit=[cache objectForKey:font]; if (hit) return hit.doubleValue;
    CGFloat digit=0,unit=0;
    for (int n=0;n<10;n++) digit=MAX(digit,SBCPUTextFPSGlyphExtent([NSString stringWithFormat:@"%d",n],font));
    for (NSString *s in @[@"MB",@"GB",@"TB",@"PB",@"EB"]) unit=MAX(unit,SBCPUTextFPSGlyphExtent(s,font));
    CGFloat width=ceil(SBCPUTextFPSGlyphExtent(@"RAM",font)+5*digit+SBCPUTextFPSGlyphExtent(@".",font)+unit)+4;
    width=MAX(width,ceil(SBCPUTextFPSGlyphExtent(@"RAM--",font))+4);
    [cache setObject:@(width) forKey:font]; return width;
}
/* Keep all ten original metric identities/order and network pairing unchanged.
   RAM is appended. With bit 10 off, geometry is exactly the 5.08 geometry. */
static inline double SBCPUTextSlotsLayoutMemory(unsigned mask,double font,double available,double gap,
    int dual,double fpsWidth,double memoryWidth,SBCPUTextSlot slots[11]) {
    double height=SBCPUTextSlotsLayoutNetworkFPS(mask&1023u,font,available,gap,dual,fpsWidth,slots);
    SBCPUTextSlot empty={0,0,0,0}; slots[10]=empty;
    if (!(mask&(1u<<10))) return height;
    double x=0,y=0,h=font*1.4;
    for (int i=0;i<10;i++) if (mask&(1u<<i)) { x=slots[i].x+slots[i].width; y=slots[i].y; }
    double width=fmin(memoryWidth,fmax(0,available));
    double candidate=x>0?x+SBCPUTextSeparatorWidth(font,gap):0;
    if (x>0 && candidate+width>available) { candidate=0; y+=h; }
    SBCPUTextSlot frame={candidate,y,width,h}; slots[10]=frame;
    return fmax(height,y+h);
}
#endif
