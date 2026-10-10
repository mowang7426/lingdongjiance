#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "../SBCPURefreshRequestPolicy.h"
int main(void) {
    assert(SBCPURefreshHardware120("iPhone15,3")); /* iPhone14ProMax */
    assert(SBCPURefreshHardware120("iPhone14,3"));
    assert(SBCPURefreshHardware120("iPad16,6"));
    assert(!SBCPURefreshHardware120("iPhone14,8"));
    assert(!SBCPURefreshHardware120("iPhone15,5"));
    assert(!SBCPURefreshHardware120("future")); assert(!SBCPURefreshHardware120(NULL));
    assert(!strlen(SBCPURefreshPauseReason(1,120,1,1,0,1,1,0,0)));
    assert(!strlen(SBCPURefreshPauseReason(1,120,1,1,0,1,1,0,1)));
    assert(strlen(SBCPURefreshPauseReason(0,120,1,1,0,1,1,0,0)));
    assert(strlen(SBCPURefreshPauseReason(1,60,1,1,0,1,1,0,0)));
    assert(strlen(SBCPURefreshPauseReason(1,120,0,1,0,1,1,0,0)));
    assert(strlen(SBCPURefreshPauseReason(1,120,1,0,0,1,1,0,0)));
    assert(strlen(SBCPURefreshPauseReason(1,120,1,1,1,1,1,0,0)));
    assert(strlen(SBCPURefreshPauseReason(1,120,1,1,0,0,1,0,0)));
    assert(strlen(SBCPURefreshPauseReason(1,120,1,1,0,1,0,0,0)));
    assert(strlen(SBCPURefreshPauseReason(1,120,1,1,0,1,1,1,0)));
    for (int thermal=2;thermal<=3;thermal++) assert(strlen(SBCPURefreshPauseReason(1,120,1,1,0,1,1,0,thermal)));
    puts("PASS refresh request: real120 whitelist, default OFF, absent ABI, lock/AOD, unknown state, display off, LPM, serious/critical thermal");
    return 0;
}
