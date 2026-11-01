#include "../SBCPUTextOnlyPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    for (int configured=0; configured<2; configured++) {
        assert(SBCPUTextOnlyDockEffective(configured, 1) == 0);
        assert(SBCPUTextOnlyDockEffective(configured, 0) == configured);
    }
    assert(SBCPUTextOnlyTop(1, 59, 1) == 0);
    assert(SBCPUTextOnlyTop(1, 0, 0) == 0);
    assert(SBCPUTextOnlyTop(0, 59, 0) == 67);
    assert(SBCPUTextOnlyTop(0, 59, 1) == 61);
    assert(SBCPUTextOnlyTop(0, 0, 0) == 20);
    assert(SBCPUTextOnlyAnchorX(0, 390, 60) == 64);
    assert(SBCPUTextOnlyAnchorX(1, 390, 60) == 195);
    assert(SBCPUTextOnlyAnchorX(2, 390, 60) == 326);
    assert(SBCPUTextOnlyAnchorX(1, 844, 60) == 422);
    assert(SBCPUTextOnlyBound(7, 8, 24, 13) == 8);
    assert(SBCPUTextOnlyBound(25, 8, 24, 13) == 24);
    assert(SBCPUTextOnlyBound(NAN, 8, 24, 13) == 13);
    assert(SBCPUTextOnlyBound(INFINITY, -1000, 1000, 0) == 0);
    assert(SBCPUTextOnlyBound(-2000, -1000, 1000, 0) == -1000);
    assert(SBCPUTextOnlyAvailableWidth(320, 568, 0) == 312);
    assert(SBCPUTextOnlyAvailableWidth(320, 568, 1) == 560);
    assert(SBCPUTextOnlyFitFont(800, 312, 13) == 8);
    assert(SBCPUTextOnlyFitFont(100, 312, 13) == 13);
    assert(SBCPUTextOnlyFitFont(NAN, 312, 13) == 13);
    assert(SBCPUTextOnlyFitFont(10000, 120, 24) == 8);
    assert(SBCPUTextOnlyFitFont(400, 312, 13) > 8);
    assert(SBCPUTextOnlyFitFont(400, 312, 13) < 13);
    puts("PASS: text-only dock, Island margin, three anchors, narrow layout and font bounds");
    return 0;
}
