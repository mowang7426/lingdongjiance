#ifndef SBCPU_TEXT_SLOT_POLICY_H
#define SBCPU_TEXT_SLOT_POLICY_H
#include <stddef.h>
#include <math.h>
/* 4.97 stored 4pt padding in each slot width. Make it an actual inter-slot gap. */
static inline double SBCPUTextDataGap(double gap) {
    return !isfinite(gap) ? 4 : (gap < -15 ? -15 : (gap > 12 ? 12 : gap));
}
/* A separator owns real space; negative legacy gaps compact padding only. */
static inline double SBCPUTextSeparatorWidth(double font, double gap) {
    return fmax(font*.55, font*.55 + SBCPUTextDataGap(gap));
}
typedef struct { double x,y,width,height; } SBCPUTextSlot;
/* Widths depend only on metric identity/font/configuration, NEVER current values. */
static inline double SBCPUTextSlotWidth(int metric, double font, double available) {
    static const int cells[10] = {10,9,6,8,7,9,10,10,10,10};
    double width = cells[metric] * font * .65;
    /* FPS has proportional uppercase letters even in a monospaced-DIGIT font.
       Reserve a stable floor plus trailing rasterization clearance. UIKit may
       enlarge this at font/configuration time, never from the sampled value. */
    if (metric == 2) width = font * 4.5 + 2;
    double usable = available > 0 ? available : 0;
    return width < usable ? width : usable;
}
static inline double SBCPUTextSlotsLayoutFPS(unsigned mask, double font, double available, double gap, double fpsWidth, SBCPUTextSlot slots[10]) {
    double x=0,y=0,h=font*1.4;
    gap=SBCPUTextSeparatorWidth(font,gap);
    for (int i=0;i<10;i++) {
        SBCPUTextSlot empty={0,0,0,0}; slots[i]=empty;
        if (!(mask & (1u<<i))) continue;
        double width=SBCPUTextSlotWidth(i,font,available);
        if (i==2 && isfinite(fpsWidth) && fpsWidth>width) width=fmin(fpsWidth,fmax(0,available));
        double candidate = x>0 ? x+gap : x;
        /* Negative gaps compact adjacent fixed slots, but never escape left. */
        if (candidate < 0) candidate=0;
        /* Treat the enabled network directions as an adjacent pair when it fits. */
        double required=width;
        if (i==8 && (mask&(1u<<9))) {
            double pair=width+gap+SBCPUTextSlotWidth(9,font,available);
            if (pair<=available) required=pair;
        }
        if (x>0 && candidate+required>available) { x=0; y+=h; }
        else x=candidate;
        SBCPUTextSlot frame={x,y,width,h}; slots[i]=frame; x+=width;
    }
    return mask ? y+h : 1;
}
/* Portable default retains a generous FPS floor without UIKit dependencies. */
static inline double SBCPUTextSlotsLayout(unsigned mask, double font, double available, double gap, SBCPUTextSlot slots[10]) {
    return SBCPUTextSlotsLayoutFPS(mask,font,available,gap,0,slots);
}
/* Only the final network pair is a stacked block. All earlier metrics retain
   their natural fixed-slot wrapping, font size and horizontal data gaps. */
static inline double SBCPUTextSlotsLayoutNetworkFPS(unsigned mask, double font, double available, double gap,
                                                int networkDual, double fpsWidth, SBCPUTextSlot slots[10]) {
    if (!networkDual || (mask & (3u<<8)) != (3u<<8))
        return SBCPUTextSlotsLayoutFPS(mask,font,available,gap,fpsWidth,slots);
    SBCPUTextSlotsLayoutFPS(mask & ~(3u<<8),font,available,gap,fpsWidth,slots);
    double x=0,y=0,h=font*1.4;
    for (int i=0;i<8;i++) if (mask & (1u<<i)) {
        x=slots[i].x+slots[i].width; y=slots[i].y;
    }
    double width=SBCPUTextSlotWidth(8,font,available);
    double candidate=x>0 ? x+SBCPUTextSeparatorWidth(font,gap) : 0;
    if (x>0 && candidate+width>available) { candidate=0; y+=h; }
    SBCPUTextSlot up={candidate,y,width,h}; slots[8]=up;
    SBCPUTextSlot down={candidate,y+h,width,h}; slots[9]=down;
    return y+2*h;
}
static inline double SBCPUTextSlotsLayoutNetwork(unsigned mask, double font, double available, double gap,
                                                int networkDual, SBCPUTextSlot slots[10]) {
    return SBCPUTextSlotsLayoutNetworkFPS(mask,font,available,gap,networkDual,0,slots);
}
/* One dot before each adjacent block on the same configured row. No leading,
   trailing or stacked up/down dot. Disabled metrics have no placeholder. */
static inline SBCPUTextSlot SBCPUTextSeparatorFrame(unsigned mask, int metric, int dual,
                                                    const SBCPUTextSlot slots[10]) {
    SBCPUTextSlot empty={0,0,0,0};
    if (!(mask&(1u<<metric)) || (dual && metric==9 && (mask&(1u<<8)))) return empty;
    for (int j=metric-1;j>=0;j--) if (mask&(1u<<j)) {
        if (slots[j].y!=slots[metric].y) return empty;
        double end=slots[j].x+slots[j].width;
        SBCPUTextSlot dot={end,slots[metric].y,slots[metric].x-end,slots[metric].height};
        return dot.width>0 ? dot : empty;
    }
    return empty;
}
static inline int SBCPUTextNetworkNeeded(int enabled, int visible, unsigned first, unsigned second) {
    return enabled && visible && ((first|second)&(3u<<8));
}
/* Existing view must be torn down whenever its owner/mode is unavailable. */
static inline int SBCPUTextHUDShouldExist(int enabled, int mode, int window, int host) {
    return enabled && mode && window && host;
}
#endif
