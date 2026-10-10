#include "../Policy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(U120Eligible(0,0,0));
    assert(U120Eligible(0,60,0));
    assert(U120Eligible(60,120,120));
    assert(U120Eligible(0,120,30));
    assert(!U120Eligible(20,30,30));
    assert(!U120Eligible(0,59.99f,59.99f));
    assert(!U120Eligible(NAN,120,120));
    assert(!U120Eligible(0,INFINITY,120));
    assert(!U120Eligible(-1,120,120));
    assert(!U120Eligible(121,120,120));
    assert(!U120Eligible(0,60,120));
    unsigned cases=0;
    for (int e=0;e<2;e++) for(int hw=60;hw<=120;hw+=60)
    for(int lock=0;lock<2;lock++) for(int low=0;low<2;low++)
    for(int thermal=0;thermal<4;thermal++) for(int main=0;main<2;main++) {
        assert(U120Safe(e,hw,lock,low,thermal,main) ==
               (e && hw==120 && !lock && !low && thermal==0 && main));
        ++cases;
    }
    printf("PASS policy: 11 range assertions + %u safety combinations\n",cases);
    return 0;
}
