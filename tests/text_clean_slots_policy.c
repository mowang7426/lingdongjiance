#include <assert.h>
#include <string.h>
#include "../SBCPUTextSlotPolicy.h"
int main(void) {
    const char *values[]={"0","--","-3mA","-99999mA","999FPS","999999999999999999mA","999B/s","1.0K/s","99.9M/s","1.0G/s"};
    const double widths[]={64,320,390,844};
    for (unsigned mask=0;mask<1024;mask++) for (int dual=0;dual<2;dual++)
    for (int fs=8;fs<=24;fs+=4) for (unsigned w=0;w<4;w++) {
        SBCPUTextSlot slots[10],next[10];
        double height=SBCPUTextSlotsLayoutNetwork(mask,fs,widths[w],4,dual,slots);
        for (unsigned v=0;v<sizeof(values)/sizeof(values[0]);v++) {
            assert(strlen(values[v])); /* Content never enters placement API. */
            assert(SBCPUTextSlotsLayoutNetwork(mask,fs,widths[w],4,dual,next)==height);
            assert(memcmp(slots,next,sizeof(slots))==0);
            int previous=-1;
            for (int i=0;i<10;i++) {
                SBCPUTextSlot dot=SBCPUTextSeparatorFrame(mask,i,dual,slots);
                SBCPUTextSlot dotNext=SBCPUTextSeparatorFrame(mask,i,dual,next);
                assert(memcmp(&dot,&dotNext,sizeof(dot))==0);
                if (!(mask&(1u<<i))) { assert(slots[i].width==0 && dot.width==0); continue; }
                int stacked=dual && i==9 && (mask&(1u<<8));
                int expected=previous>=0 && slots[previous].y==slots[i].y && !stacked;
                assert((dot.width>0)==expected);
                if (expected) {
                    assert(dot.x==slots[previous].x+slots[previous].width);
                    assert(fabs(dot.x+dot.width-slots[i].x)<1e-9);
                    assert(dot.y==slots[i].y);
                }
                previous=i;
            }
        }
    }
    return 0;
}
