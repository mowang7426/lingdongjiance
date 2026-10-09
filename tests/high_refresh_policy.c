#include "../SBCPUHighRefreshPolicy.h"
#include <assert.h>
#include <stdio.h>
static void same(SBHRRange a, SBHRRange b) {
    assert((isnan(a.minimum) && isnan(b.minimum)) || a.minimum == b.minimum);
    assert((isnan(a.maximum) && isnan(b.maximum)) || a.maximum == b.maximum);
    assert((isnan(a.preferred) && isnan(b.preferred)) || a.preferred == b.preferred);
}
int main(void) {
    int64_t values[] = {0,30,59,60,90,120,144,-1,-120,INT64_MIN,INT64_MAX};
    SBHRRange ranges[] = {{0,0,0},{0,30,30},{30,59,59},{60,59,59},
        {0,60,0},{0,59,60},{30,90,30},{60,120,120},{60,144,144},
        {-1,-30,-30},{0,59.999f,59.999f},{NAN,120,120},
        {0,NAN,120},{0,120,NAN},{INFINITY,120,120},{0,INFINITY,0},
        {0,0,INFINITY},{0,-INFINITY,120}};
    for (int enabled=0; enabled<2; ++enabled) for (int supported=0; supported<2; ++supported) {
        bool active = enabled && supported;
        for (unsigned i=0; i<sizeof(values)/sizeof(values[0]); ++i) {
            assert(SBHRFPS(values[i],enabled,supported) == (active && values[i]>59 ? 120 : values[i]));
            assert(SBHRMaximum(values[i],enabled,supported) == (active ? 120 : values[i]));
        }
        for (unsigned i=0; i<sizeof(ranges)/sizeof(ranges[0]); ++i) {
            bool transform = active && (i==0 || (i>=4 && i<=8));
            same(SBHRFrameRange(ranges[i],enabled,supported), transform ? (SBHRRange){60,120,120} : ranges[i]);
        }
    }
    assert(SBHRABI("q",2,"@",":",NULL,"q",NULL));
    assert(SBHRABI("v",3,"@",":","q","v","q"));
    assert(SBHRABI("v",3,"@",":","{CAFrameRateRange=fff}","v","{CAFrameRateRange=fff}"));
    const char *bad[] = {"f","d","Q","i","v", "rq", NULL};
    for (unsigned i=0;i<sizeof(bad)/sizeof(bad[0]);++i)
        assert(!SBHRABI(bad[i],2,"@",":",NULL,"q",NULL));
    assert(!SBHRABI("q",3,"@",":","q","q",NULL));
    assert(!SBHRABI("q",1,"@",":",NULL,"q",NULL));
    assert(!SBHRABI("q",2,"#",":",NULL,"q",NULL));
    assert(!SBHRABI("q",2,"@","@",NULL,"q",NULL));
    assert(!SBHRABI("v",3,"@",":",NULL,"v","q"));
    assert(!SBHRABI("v",3,"@",":","Q","v","q"));
    assert(!SBHRABI("v",3,"@",":","{CAFrameRateRange=ddd}","v","{CAFrameRateRange=fff}"));
    puts("high-refresh production policy + ABI tests passed");
}
