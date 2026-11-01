#include "../SBCPUFloatingLockPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(SBCPULockedCoordinate(120, 390, 40) == 120);
    assert(SBCPULockedCoordinate(120, 390, 15) == 120); /* folded */
    assert(SBCPULockedCoordinate(120, 390, 100) == 120); /* expanded */
    assert(SBCPULockedCoordinate(370, 390, 40) == 350); /* keep unlock reachable */
    assert(SBCPULockedCoordinate(370, 844, 40) == 370); /* restore original anchor */
    assert(SBCPULockedCoordinate(-20, 390, 40) == 40);
    assert(SBCPULockedCoordinate(120, 100, 80) == 50); /* oversized view */
    assert(SBCPULockedCoordinate(NAN, 390, 40) == 0);
    assert(SBCPULockedCoordinate(120, 0, 40) == 0);
    int blocked = SBCPUPanLockBlocked(1,0,1);
    double center = 100;
    assert(blocked);
    for (int i=0; i<120; ++i) {
        blocked = SBCPUPanLockBlocked(1,blocked,0);
        if (!blocked) center += 10;
        assert(center == 100); /* locked-pan and refresh never move */
    }
    blocked = SBCPUPanLockBlocked(0,blocked,0);
    assert(blocked); /* unlocking cannot revive the old pan */
    blocked = SBCPUPanLockBlocked(0,blocked,1);
    assert(!blocked); /* new unlocked drag allowed */
    if (!blocked) center += 10;
    assert(center == 110);
    assert(SBCPUPanLockBlocked(1,0,0)); /* locking during pan blocks remaining moves */
    puts("floating lock geometry and locked/unlocked pan sequence regression passed");
    return 0;
}
