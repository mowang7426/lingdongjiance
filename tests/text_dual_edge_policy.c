#include <assert.h>
#include <string.h>
#include "../SBCPUTextSlotPolicy.h"
#include "../SBCPUTextAnchorPolicy.h"
int main(void) {
    SBCPUTextSlot a[10],b[10];
    for (int gap=-15;gap<=12;gap++) {
        SBCPUTextSlotsLayoutRows(768,13,390,gap,0,a);
        assert(a[8].width==10*13*.65);
        assert(a[9].x==a[8].width+gap && a[9].y==a[8].y);
        for (int direction=8;direction<=9;direction++) {
            SBCPUTextSlotsLayoutRows(1u<<direction,13,390,gap,0,a);
            assert(a[direction].x==0 && a[direction].y==0);
            assert(a[17-direction].width==0);
        }
    }
    for (unsigned mask=0;mask<1024;mask++) for (int dual=0;dual<2;dual++)
    for (int fs=8;fs<=24;fs+=4) for (int w=160;w<=844;w+=171)
    for (int gap=-15;gap<=12;gap+=3) {
        double h=SBCPUTextSlotsLayoutRows(mask,fs,w,gap,dual,a);
        assert(SBCPUTextSlotsLayoutRows(mask,fs,w,gap,dual,b)==h);
        assert(memcmp(a,b,sizeof(a))==0);
        for (int i=0;i<10;i++) {
            if (!(mask&(1u<<i))) { assert(a[i].width==0); continue; }
            assert(a[i].x>=0 && a[i].x+a[i].width<=w+.00001);
            assert(a[i].y+a[i].height<=h+.00001);
            if (dual) assert(a[i].y==0 || a[i].y==a[i].height);
        }
        if (dual && (mask&768)==768) assert(a[8].y==a[9].y);
        if (!dual) {
            assert(SBCPUTextSlotsLayout(mask,fs,w,gap,b)==h);
            assert(memcmp(a,b,sizeof(a))==0);
        }
    }
    double x=123.123456789, y=70.87654321;
    assert(SBCPUTextAnchorOffsetsMatch(x,y,(float)x,(float)y));
    assert(!SBCPUTextAnchorOffsetsMatch(x,y,x+8,y));
    assert(!SBCPUTextAnchorOffsetsMatch(NAN,y,x,y));
    for (int r=-1;r<=2;r++) {
        double pw=390,ph=844,w=(r==1||r==-1)?ph:pw,h=(r==1||r==-1)?pw:ph;
        double hw=85.15,hh=18.2,left=0,right=(r==0?0:47),bottom=34;
        SBCPUTextPoint edge={w-right-hw,hh+70.123456};
        SBCPUTextPoint physical=SBCPUTextFromLogical(edge,pw,ph,r);
        SBCPUTextPoint logical=SBCPUTextToLogical(physical,pw,ph,r);
        SBCPUTextAnchor anchor=SBCPUTextCaptureAnchor(logical,w,h,hw,hh,left,0,right,bottom);
        assert(anchor.right && anchor.xMargin<.00001);
        SBCPUTextPoint restored=SBCPUTextResolveAnchor(anchor,w,h,hw,hh,left,0,right,bottom);
        assert(fabs(restored.x+hw-(w-right))<.00001);
        restored=SBCPUTextResolveAnchor(anchor,h,w,hw,hh,47,0,0,bottom);
        assert(fabs(restored.x+hw-h)<.00001);
    }
    return 0;
}
