#ifndef SBCPU_TEXT_SLOT_POLICY_H
#define SBCPU_TEXT_SLOT_POLICY_H
#include <stddef.h>
#include <math.h>
/* 4.97 stored 4pt padding in each slot width. Make it an actual inter-slot gap. */
static inline double SBCPUTextDataGap(double gap) {
    return !isfinite(gap) ? 4 : (gap < -15 ? -15 : (gap > 12 ? 12 : gap));
}
typedef struct { double x,y,width,height; } SBCPUTextSlot;
/* Widths depend only on metric identity/font/configuration, NEVER current values. */
static inline double SBCPUTextSlotWidth(int metric, double font, double available) {
    static const int cells[10] = {12,10,9,10,11,13,13,13,10,10};
    double width = cells[metric] * font * .65;
    double usable = available > 0 ? available : 0;
    return width < usable ? width : usable;
}
static inline double SBCPUTextSlotsLayout(unsigned mask, double font, double available, double gap, SBCPUTextSlot slots[10]) {
    double x=0,y=0,h=font*1.4;
    gap=SBCPUTextDataGap(gap);
    for (int i=0;i<10;i++) {
        SBCPUTextSlot empty={0,0,0,0}; slots[i]=empty;
        if (!(mask & (1u<<i))) continue;
        double width=SBCPUTextSlotWidth(i,font,available);
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
/* Only the final network pair is a stacked block. All earlier metrics retain
   their natural fixed-slot wrapping, font size and horizontal data gaps. */
static inline double SBCPUTextSlotsLayoutNetwork(unsigned mask, double font, double available, double gap,
                                                int networkDual, SBCPUTextSlot slots[10]) {
    if (!networkDual || (mask & (3u<<8)) != (3u<<8))
        return SBCPUTextSlotsLayout(mask,font,available,gap,slots);
    SBCPUTextSlotsLayout(mask & ~(3u<<8),font,available,gap,slots);
    double x=0,y=0,h=font*1.4;
    for (int i=0;i<8;i++) if (mask & (1u<<i)) {
        x=slots[i].x+slots[i].width; y=slots[i].y;
    }
    double width=SBCPUTextSlotWidth(8,font,available);
    double candidate=x>0 ? fmax(0,x+SBCPUTextDataGap(gap)) : 0;
    if (x>0 && candidate+width>available) { candidate=0; y+=h; }
    SBCPUTextSlot up={candidate,y,width,h}; slots[8]=up;
    SBCPUTextSlot down={candidate,y+h,width,h}; slots[9]=down;
    return y+2*h;
}
static inline int SBCPUTextNetworkNeeded(int enabled, int visible, unsigned first, unsigned second) {
    return enabled && visible && ((first|second)&(3u<<8));
}
/* Existing view must be torn down whenever its owner/mode is unavailable. */
static inline int SBCPUTextHUDShouldExist(int enabled, int mode, int window, int host) {
    return enabled && mode && window && host;
}
#endif
