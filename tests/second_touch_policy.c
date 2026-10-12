#include "../SBCPUSecondTouchPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    for (int locked=0; locked<2; ++locked)
        for (int enabled=0; enabled<2; ++enabled)
            for (int visible=0; visible<2; ++visible)
                for (int modal=0; modal<2; ++modal)
                    assert(SBCPUSecondTouchIgnored(locked,enabled,visible,modal) ==
                        !(enabled && visible && !locked && !modal));
    /* Lock -> unlock immediately, no refresh tick needed. */
    assert(SBCPUSecondTouchIgnored(1,1,1,0));
    assert(!SBCPUSecondTouchIgnored(0,1,1,0));
    puts("PASS second window whole-surface lock / unlock policy (16 states)");
    return 0;
}
