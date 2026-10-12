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
/* Split enabled identities once, not live values. Keep the network pair together.
   Fit the two groups to available width with one stable font scale. */
static inline double SBCPUTextSlotsLayoutRows(unsigned mask, double font, double available, double gap,
                                             int dual, SBCPUTextSlot slots[10]) {
    if (!dual) return SBCPUTextSlotsLayout(mask,font,available,gap,slots);
    int ids[10], count=0;
    for (int i=0;i<10;i++) if (mask&(1u<<i)) ids[count++]=i;
    int split=(count+1)/2;
    if (split<count && ids[split-1]==8 && ids[split]==9) --split;
    if (!split && count) split=count;
    gap=SBCPUTextDataGap(gap);
    double widths[2]={0,0}, cells[2]={0,0};
    int lengths[2]={split,count-split};
    for (int n=0;n<count;n++) cells[n<split?0:1]+=SBCPUTextSlotWidth(ids[n],font,1e9);
    double scale=1;
    for (int r=0;r<2;r++) {
        widths[r]=cells[r]+(lengths[r]>0?lengths[r]-1:0)*gap;
        if (widths[r]>available) {
            double fit=(available-(lengths[r]-1)*gap)/cells[r];
            if (fit<scale) scale=fit;
        }
    }
    if (scale<.01) scale=.01;
    double h=font*scale*1.4, x=0;
    for (int i=0;i<10;i++) { SBCPUTextSlot empty={0,0,0,0}; slots[i]=empty; }
    for (int n=0;n<count;n++) {
        if (n==split) x=0;
        double width=SBCPUTextSlotWidth(ids[n],font*scale,available);
        SBCPUTextSlot frame={x,n<split?0:h,width,h}; slots[ids[n]]=frame;
        x=fmax(0,x+width+gap);
    }
    return count ? h*(count>split?2:1) : 1;
}
static inline int SBCPUTextNetworkNeeded(int enabled, int visible, unsigned first, unsigned second) {
    return enabled && visible && ((first|second)&(3u<<8));
}
/* Existing view must be torn down whenever its owner/mode is unavailable. */
static inline int SBCPUTextHUDShouldExist(int enabled, int mode, int window, int host) {
    return enabled && mode && window && host;
}
#endif
