#ifndef SBCPU_TEXT_SLOT_POLICY_H
#define SBCPU_TEXT_SLOT_POLICY_H
#include <stddef.h>
#include <math.h>
/* 4.97 stored 4pt padding in each slot width. Make it an actual inter-slot gap. */
static inline double SBCPUTextDataGap(double gap) {
    return !isfinite(gap) ? 4 : (gap < 0 ? 0 : (gap > 12 ? 12 : gap));
}
typedef struct { double x,y,width,height; } SBCPUTextSlot;
/* Widths depend only on metric identity/font/configuration, NEVER current values. */
static inline double SBCPUTextSlotWidth(int metric, double font, double available) {
    static const int cells[10] = {12,10,9,10,11,13,13,13,14,14};
    double width = cells[metric] * font * .65;
    return width < available ? width : available;
}
static inline double SBCPUTextSlotsLayout(unsigned mask, double font, double available, double gap, SBCPUTextSlot slots[10]) {
    double x=0,y=0,h=font*1.4;
    gap=SBCPUTextDataGap(gap);
    for (int i=0;i<10;i++) {
        SBCPUTextSlot empty={0,0,0,0}; slots[i]=empty;
        if (!(mask & (1u<<i))) continue;
        double width=SBCPUTextSlotWidth(i,font,available);
        if (x>0 && x+gap+width>available) { x=0; y+=h; }
        if (x>0) x+=gap;
        SBCPUTextSlot frame={x,y,width,h}; slots[i]=frame; x+=width;
    }
    return mask ? y+h : 1;
}
static inline int SBCPUTextNetworkNeeded(int enabled, int visible, unsigned first, unsigned second) {
    return enabled && visible && ((first|second)&(3u<<8));
}
/* Existing view must be torn down whenever its owner/mode is unavailable. */
static inline int SBCPUTextHUDShouldExist(int enabled, int mode, int window, int host) {
    return enabled && mode && window && host;
}
#endif
