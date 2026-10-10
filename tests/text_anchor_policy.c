#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../SBCPUTextAnchorPolicy.h"
static void closeTo(double a,double b) { assert(fabs(a-b)<0.00001); }
static void roundTrip(int rotation) {
    double width = 430, height = 932, hw = 145, hh = 9;
    SBCPUTextPoint portrait = {hw+4,hh+59};
    SBCPUTextAnchor stored = SBCPUTextCaptureAnchor(portrait,width,height,hw,hh,4,59,4,34);
    assert(!stored.right && !stored.bottom); closeTo(stored.xMargin,0); closeTo(stored.yMargin,0);
    for (int i=0;i<12;i++) {
        /* Landscape top-left is the display's top-left, NOT portrait x/y. */
        SBCPUTextPoint logical = SBCPUTextResolveAnchor(stored,height,width,hw,hh,59,4,59,21);
        closeTo(logical.x,59+hw); closeTo(logical.y,4+hh);
        SBCPUTextPoint physical = SBCPUTextFromLogical(logical,width,height,rotation);
        SBCPUTextPoint displayed = SBCPUTextToLogical(physical,width,height,rotation);
        closeTo(displayed.x,logical.x); closeTo(displayed.y,logical.y);
        assert(fabs(physical.x-portrait.x)>10 || fabs(physical.y-portrait.y)>10);
        SBCPUTextPoint back = SBCPUTextResolveAnchor(stored,width,height,hw,hh,4,59,4,34);
        closeTo(back.x,portrait.x); closeTo(back.y,portrait.y);
    }
    /* Already oriented window: mapping identity, do not rotate twice. */
    SBCPUTextPoint landscape = SBCPUTextResolveAnchor(stored,height,width,hw,hh,59,4,59,21);
    SBCPUTextPoint oriented = SBCPUTextFromLogical(landscape,height,width,0);
    closeTo(oriented.x,landscape.x); closeTo(oriented.y,landscape.y);
    /* Unlock/drag/relock/restore use displayed coordinates and unchanged margins. */
    SBCPUTextPoint dragged = {landscape.x+37,landscape.y+25};
    SBCPUTextAnchor relocked = SBCPUTextCaptureAnchor(dragged,height,width,hw,hh,59,4,59,21);
    SBCPUTextAnchor restored = relocked;
    closeTo(restored.xMargin,37); closeTo(restored.yMargin,25);
    SBCPUTextPoint p = SBCPUTextResolveAnchor(restored,width,height,hw,hh,4,59,4,34);
    closeTo(p.x,hw+4+37); closeTo(p.y,hh+59+25);
    /* Font/content bounds changes preserve top edge, not the old center. */
    p = SBCPUTextResolveAnchor(stored,width,height,100,12,4,59,4,34);
    closeTo(p.x,104); closeTo(p.y,71);
    /* Temporary safe-area/clamp correction must never mutate persisted margins. */
    (void)SBCPUTextResolveAnchor(restored,200,100,130,50,30,30,30,30);
    closeTo(restored.xMargin,37); closeTo(restored.yMargin,25);
}
int main(void) {
    roundTrip(1); roundTrip(-1);
    SBCPUTextPoint p = {12,23};
    SBCPUTextPoint q = SBCPUTextFromLogical(p,430,932,2);
    q = SBCPUTextToLogical(q,430,932,2); closeTo(q.x,p.x); closeTo(q.y,p.y);
    SBCPUTextAnchor a = {1,1,8,13};
    q = SBCPUTextResolveAnchor(a,932,430,130,9,59,4,59,21);
    closeTo(q.x,932-59-130-8); closeTo(q.y,430-21-9-13);
    puts("PASS text anchor: top-left both-landscape round-trip, oriented window, upside down, unlock/drag/relock/restore, safe areas/font geometry");
    return 0;
}
