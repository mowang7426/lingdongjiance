#include <assert.h>
#include "../SBCPULock120Policy.h"
int main(void) {
    assert(!SB120Active(0,120,1,0,0));
    assert(SB120Active(1,120,1,0,0));
    assert(!SB120Active(1,120,1,1,0));
    assert(!SB120Active(1,120,1,0,2));
    assert(SB120FPS(60, true)==60 && SB120FPS(90,true)==120);
    SB120Range r={60,120,60}; assert(SB120SelectRange(r,true).preferred==60);
    r.minimum=60; r.maximum=120; r.preferred=120; assert(SB120SelectRange(r,true).minimum==120);
    return 0;
}
