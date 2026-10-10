#include <assert.h>
#include <stdio.h>
#include "../SBCPUDynamicRangePolicy.h"
int main(void) {
    assert(SBCPUDynamicRangeEligible(30,60,60));
    assert(SBCPUDynamicRangeEligible(24,80,0));
    assert(SBCPUDynamicRangeEligible(120,120,120));
    assert(!SBCPUDynamicRangeEligible(0,0,0));
    assert(!SBCPUDynamicRangeEligible(-1,60,60));
    assert(!SBCPUDynamicRangeEligible(80,60,60));
    assert(!SBCPUDynamicRangeEligible(30,60,120));
    assert(!SBCPUDynamicRangeEligible(30,144,60));
    assert(!SBCPUDynamicRangeEligible(NAN,60,60));
    assert(!SBCPUDynamicRangeEligible(0,INFINITY,60));
    assert(!SBCPUDynamicRangeEligible(0,60,NAN));
    puts("PASS dynamic range: finite valid <=120 only; preserve defaults/invalid/higher capability ranges");
    return 0;
}
