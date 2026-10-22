#include <assert.h>
#include <math.h>
#include "../hello120hz/Core/H120Policy.h"
int main(void) {
 assert(!H120ClientEnabled(false,false)); assert(!H120ClientEnabled(false,true));
 assert(!H120ClientEnabled(true,true)); assert(H120ClientEnabled(true,false));
 float rates[]={10,30,60,80,120};
 for(unsigned i=0;i<5;i++) assert(H120NormalizeFPS(rates[i])==rates[i]);
 assert(H120NormalizeFPS(NAN)==120); assert(H120NormalizeFPS(INFINITY)==120);
 assert(H120NormalizeFPS(0)==120); assert(H120NormalizeFPS(-1)==120);
 assert(!H120SystemAllowsOverride(false,false,0));
 assert(!H120SystemAllowsOverride(true,true,0));
 assert(!H120SystemAllowsOverride(true,false,2));
 assert(H120ChooseCadence(4,0,2)==4); assert(H120ChooseCadence(4,2,3)==4);
 return 0;
}
