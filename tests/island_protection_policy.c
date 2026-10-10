#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../SBCPUTextAnchorPolicy.h"
#include "../SBCPUTextOnlyPolicy.h"
static void eq(double a, double b) { assert(fabs(a-b)<0.00001); }
int main(void) {
    for (int enabled=0; enabled<=1; ++enabled) {
        eq(SBCPUFloatingProtectedTop(1,enabled,59),0);
        eq(SBCPUFloatingProtectedTop(0,enabled,67),enabled?67:0);
        eq(SBCPUFloatingProtectedTop(0,enabled,61),enabled?61:0);
        for (int r=-1; r<=2; ++r) {
            double w=(r==1||r==-1)?932:430;
            double h=(r==1||r==-1)?430:932;
            double left=w==932?59:4, right=left, bottom=34, hw=100, hh=9;
            double top=SBCPUFloatingProtectedTop(1,enabled,59);
            for (int preset=0; preset<3; ++preset) {
                double x=SBCPUTextSafeCoordinate(SBCPUTextOnlyAnchorX(preset,w,hw),left+hw,w-right-hw);
                SBCPUTextPoint dragged={x,SBCPUTextSafeCoordinate(-500,top+hh,h-bottom-hh)};
                eq(dragged.y,hh); // complete row's top edge is exactly zero
                SBCPUTextAnchor saved=SBCPUTextCaptureAnchor(dragged,w,h,hw,hh,left,top,right,bottom);
                eq(saved.yMargin,0);
                SBCPUTextPoint restored=SBCPUTextResolveAnchor(saved,w,h,hw,hh,left,top,right,bottom);
                eq(restored.x,x); eq(restored.y,hh);
                SBCPUTextPoint physical=SBCPUTextFromLogical(restored,430,932,r);
                SBCPUTextPoint display=SBCPUTextToLogical(physical,430,932,r);
                eq(display.x,restored.x); eq(display.y,hh);
                // Re-enable protection, change orientation/font, restore same persisted anchor.
                SBCPUTextPoint rotated=SBCPUTextResolveAnchor(saved,932,430,hw,12,59,
                    SBCPUFloatingProtectedTop(1,1,59),59,21);
                eq(rotated.y,12); eq(saved.yMargin,0);
                SBCPUTextPoint back=SBCPUTextResolveAnchor(saved,w,h,hw,hh,left,
                    SBCPUFloatingProtectedTop(1,1,59),right,bottom);
                eq(back.x,restored.x); eq(back.y,hh);
                eq(SBCPUTextSafeCoordinate(9999,top+hh,h-bottom-hh),h-bottom-hh);
                assert(restored.x-hw>=left && restored.x+hw<=w-right);
            }
        }
    }
    puts("PASS island protection: text top=0 on/off, capsule avoidance, presets, drag, restore, rotations, font and unchanged anchors");
    return 0;
}
