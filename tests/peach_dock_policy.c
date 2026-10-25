#include "../PeachDock/SBCPUPeachDockPolicy.h"
#include "../PeachDock/SBCPUPeachDockDockDropGeometry.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    for (int major = 14; major <= 26; ++major)
        for (int minor = 0; minor < 10; ++minor)
            assert(SBCPUPeachDockProfileApproved(major, minor) == (major == 16));
    assert(!SBCPUPeachDockProfileApproved(16, -1));
    const double widths[] = {320, 375, 390, 393, 414, 430, 844};
    for (unsigned w = 0; w < sizeof(widths)/sizeof(widths[0]); ++w) {
        double width = widths[w], pitch = SBCPUPeachDockPitch(width);
        for (unsigned capacity = 1; capacity <= 100; ++capacity) {
            for (unsigned c = 1; c <= capacity; ++c) {
                double center, fraction; unsigned column = 0;
                assert(SBCPUPeachDockDropCenterX(c, capacity, width, pitch, &center));
                assert(SBCPUPeachDockDropColumnAtX(center, capacity, width, pitch, &column, &fraction));
                assert(c == column && fraction >= 0 && fraction <= 1);
            }
        }
    }
    double x;
    assert(!SBCPUPeachDockDropCenterX(0, 100, 390, 97.5, &x));
    assert(!SBCPUPeachDockDropCenterX(101, 100, 390, 97.5, &x));
    assert(SBCPUPeachDockPitch(NAN) == 0 && SBCPUPeachDockPitch(-1) == 0);
    for (int bits = 0; bits < 16; ++bits)
        for (int thermal = 0; thermal < 4; ++thermal) {
            bool e=bits&1, low=bits&2, motion=bits&4, transparency=bits&8;
            assert(SBCPUPeachDockVisualPolicy(e,low,thermal,motion,transparency) ==
                   (e && !low && thermal < 2 && !motion && !transparency));
        }
    puts("PASS: production pitch, 35350 forward/inverse cases, iOS 16 candidate envelope, visual policy");
    return 0;
}
