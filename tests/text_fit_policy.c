#include "../SBCPUTextOnlyPolicy.h"
#include "../SBCPUTextAnchorPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    const double widths[] = {320, 375, 390, 430, 568, 844};
    const double natural[] = {0, 180, 520, 900, 3000};
    for (unsigned i=0;i<sizeof(widths)/sizeof(widths[0]);i++) {
        double w=widths[i], h=w>430?390:844;
        double left=w>430?59:4, right=left, top=0, bottom=34;
        double available=w-left-right;
        for (unsigned j=0;j<sizeof(natural)/sizeof(natural[0]);j++) {
            double font=SBCPUTextOnlyFitFont(natural[j],available,13);
            assert(font>=8 && font<=13);
            if (natural[j]+2<=available) assert(font==13);
            double scaled=natural[j]*font/13;
            double rw=fmax(1,fmin(available,ceil(scaled)+2));
            // Conservative monospaced row model: UIKit measures actual glyphs.
            double rows=fmax(1,ceil((scaled+2)/available));
            double rh=fmin(h-top-bottom,rows*ceil(font*1.3));
            assert(rw<=available && rh<=h-top-bottom);
            for (int side=0;side<2;side++) for (int base=0;base<2;base++) {
                SBCPUTextAnchor a={side,base,180,250};
                SBCPUTextPoint p=SBCPUTextResolveAnchor(a,w,h,rw/2,rh/2,left,top,right,bottom);
                assert(p.x-rw/2>=left-1e-9 && p.x+rw/2<=w-right+1e-9);
                assert(p.y-rh/2>=top-1e-9 && p.y+rh/2<=h-bottom+1e-9);
                // Drag centers far off both screen edges must clamp too.
                for (int direction=-1;direction<=1;direction+=2) {
                    double x=SBCPUTextSafeCoordinate(direction*10000,left+rw/2,w-right-rw/2);
                    double y=SBCPUTextSafeCoordinate(direction*10000,top+rh/2,h-bottom-rh/2);
                    assert(x-rw/2>=left-1e-9 && x+rw/2<=w-right+1e-9);
                    assert(y-rh/2>=top-1e-9 && y+rh/2<=h-bottom+1e-9);
                }
                for (int rotation=-1;rotation<=2;rotation++) {
                    double cw=(rotation==1||rotation==-1)?h:w;
                    double ch=(rotation==1||rotation==-1)?w:h;
                    SBCPUTextPoint c=SBCPUTextFromLogical(p,cw,ch,rotation);
                    SBCPUTextPoint back=SBCPUTextToLogical(c,cw,ch,rotation);
                    assert(fabs(back.x-p.x)<1e-9 && fabs(back.y-p.y)<1e-9);
                }
            }
        }
    }
    puts("PASS: bounded font, long/all-field rows, portrait/landscape safe margins, left/right locks, drag and rotation");
    return 0;
}
