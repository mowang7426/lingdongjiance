#ifndef SBCPU_TEXT_MEMORY_H
#define SBCPU_TEXT_MEMORY_H
#import "SBCPUTextFPSBudget.h"
#import "SBCPUMemoryMetrics.h"
static inline NSString *SBCPUTextMemoryValue(SBCPUMemoryMetrics sample) {
    if (!sample.valid) return @"RAM--";
    double used=sample.used_bytes/1048576.0, total=sample.total_bytes/1048576.0;
    if (total<1024.0) return [NSString stringWithFormat:@"RAM%.0fMB/%.0fMB",used,total];
    used/=1024.0; total/=1024.0; NSArray *units=@[@"GB",@"TB",@"PB",@"EB"];
    for (NSString *unit in units) {
        if (total<1024.0 || [unit isEqualToString:@"EB"]) return [NSString stringWithFormat:(total<10.0?@"RAM%.2f/%.2f%@":@"RAM%.1f/%.1f%@"),used,total,unit];
        used/=1024.0; total/=1024.0;
    } return @"RAM--";
}
static inline CGFloat SBCPUTextMemoryConfiguredWidth(UIFont *font) {
    static NSCache<UIFont *,NSNumber *> *cache; if (!cache) cache=[NSCache new]; NSNumber *hit=[cache objectForKey:font]; if (hit) return hit.doubleValue;
    CGFloat width=0; for (NSString *s in @[@"RAM0.00/0.00GB",@"RAM99.9/99.9GB",@"RAM999.9/999.9GB",@"RAM999MB/999MB",@"RAM--"]) width=MAX(width,ceil(SBCPUTextFPSGlyphExtent(s,font)));
    width+=4; [cache setObject:@(width) forKey:font]; return width;
}
/* Keep the original ten metric identities/order; RAM remains appended as slot 10. */
static inline double SBCPUTextSlotsLayoutMemory(unsigned mask,double font,double available,double gap,int dual,double fpsWidth,double memoryWidth,SBCPUTextSlot slots[11]) {
    double height=SBCPUTextSlotsLayoutNetworkFPS(mask&1023u,font,available,gap,dual,fpsWidth,slots); SBCPUTextSlot empty={0,0,0,0}; slots[10]=empty; if (!(mask&(1u<<10))) return height;
    double x=0,y=0,h=font*1.4; for (int i=0;i<10;i++) if (mask&(1u<<i)) { x=slots[i].x+slots[i].width; y=slots[i].y; }
    double width=fmin(memoryWidth,fmax(0,available)); double candidate=x>0?x+SBCPUTextSeparatorWidth(font,gap):0; if (x>0 && candidate+width>available) { candidate=0; y+=h; }
    SBCPUTextSlot frame={candidate,y,width,h}; slots[10]=frame; return fmax(height,y+h);
}
#endif
