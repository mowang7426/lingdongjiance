#include <assert.h>
#include <string.h>
#include "../SBCPUTextSlotPolicy.h"
int main(void) {
    const double widths[]={64,160,320,390,844};
    /* Values deliberately span decimal/digit/unit thresholds. They cannot enter
       the production placement API: rendering is separately wired to child labels. */
    const char *values[]={"9.9%","10.0%","60","120","999B/s","1.0K/s","99.9M/s","--"};
    for (unsigned mask=0;mask<1024;mask++) for (int fs=8;fs<=24;fs++)
    for (unsigned w=0;w<sizeof(widths)/sizeof(widths[0]);w++) {
        SBCPUTextSlot baseline[10],next[10];
        double height=SBCPUTextSlotsLayout(mask,fs,widths[w],baseline);
        for (unsigned v=0;v<sizeof(values)/sizeof(values[0]);v++) {
            assert(strlen(values[v])>0);
            assert(SBCPUTextSlotsLayout(mask,fs,widths[w],next)==height);
            for (int i=0;i<10;i++) {
                assert(next[i].x==baseline[i].x && next[i].y==baseline[i].y);
                assert(next[i].width==baseline[i].width && next[i].height==baseline[i].height);
                if (!(mask&(1u<<i))) { assert(next[i].width==0); continue; }
                assert(next[i].width==SBCPUTextSlotWidth(i,fs,widths[w]));
                assert(next[i].x>=0 && next[i].x+next[i].width<=widths[w]+.0001);
                assert(next[i].y+next[i].height<=height);
                for (int j=0;j<i;j++) if (mask&(1u<<j))
                    assert(next[i].y!=next[j].y || next[i].x>=next[j].x+next[j].width);
            }
        }
    }
    for (int enabled=0;enabled<2;enabled++) for (int visible=0;visible<2;visible++)
    for (unsigned a=0;a<1024;a++) for (unsigned b=0;b<1024;b++)
        assert(!!SBCPUTextNetworkNeeded(enabled,visible,a,b)==!!(enabled && visible && ((a|b)&768)));
    return 0;
}
