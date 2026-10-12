#include <assert.h>
#include <string.h>
#include "../SBCPUTextSlotPolicy.h"
int main(void) {
    assert(SBCPUTextDataGap(NAN)==4 && SBCPUTextDataGap(INFINITY)==4);
    assert(SBCPUTextDataGap(-1)==0 && SBCPUTextDataGap(13)==12);
    assert(SBCPUTextDataGap(2.5)==2.5 && SBCPUTextDataGap(4)==4);
    SBCPUTextSlot first[10],second[10];
    SBCPUTextSlotsLayout(7,13,1000,4,first);
    /* Default starts match 4.97 widths (content + 4pt trailing padding). */
    assert(first[1].x==12*13*.65+4);
    assert(first[2].x==12*13*.65+4+10*13*.65+4);
    for (int gap=0;gap<=12;gap++) {
        SBCPUTextSlotsLayout(7,13,1000,gap,second);
        assert(second[0].x==0 && second[0].width==first[0].width);
        assert(second[1].x==second[0].width+gap);
        assert(second[2].x==second[0].width+second[1].width+gap*2);
        assert(first[1].x==12*13*.65+4); /* window 1 remains independent */
    }
    SBCPUTextSlotsLayout(7,13,1000,4,second); /* apply first gap to second */
    assert(memcmp(first,second,sizeof(first))==0);
    SBCPUTextSlotsLayout(3,13,187,0,first);
    SBCPUTextSlotsLayout(3,13,187,12,second);
    assert(first[1].y==0 && second[1].y>0); /* gap alone may wrap */
    const double widths[]={64,160,320,390,844};
    /* Values deliberately span decimal/digit/unit thresholds. They cannot enter
       the production placement API: rendering is separately wired to child labels. */
    const char *values[]={"9.9%","10.0%","60","120","999B/s","1.0K/s","99.9M/s","--"};
    for (unsigned mask=0;mask<1024;mask++) for (int fs=8;fs<=24;fs++)
    for (unsigned w=0;w<sizeof(widths)/sizeof(widths[0]);w++) for (int gap=0;gap<=12;gap+=3) {
        SBCPUTextSlot baseline[10],next[10];
        double height=SBCPUTextSlotsLayout(mask,fs,widths[w],gap,baseline);
        for (unsigned v=0;v<sizeof(values)/sizeof(values[0]);v++) {
            assert(strlen(values[v])>0);
            assert(SBCPUTextSlotsLayout(mask,fs,widths[w],gap,next)==height);
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
    for (int bits=0;bits<16;bits++) {
        int exists=SBCPUTextHUDShouldExist(bits&1,bits&2,bits&4,bits&8);
        assert(!!exists==(bits==15));
        /* Close, disable, lose window, lose host must ALL clear a live HUD. */
        for (int bit=0;bit<4;bit++) {
            int closed=bits&~(1<<bit);
            assert(!SBCPUTextHUDShouldExist(closed&1,closed&2,closed&4,closed&8));
        }
    }
    return 0;
}
