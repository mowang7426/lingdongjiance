#include "../SBCPUPiPPolicy.h"
#include <assert.h>
int main(void) {
 PiPState s={PIPOff,0}; assert(PiPBegin(&s)); assert(s.phase==PIPPreparing); uint64_t g=s.generation;
 assert(!PiPBegin(&s)); assert(!PiPStart(&s,g+1)); assert(PiPStart(&s,g)); assert(PiPDidStart(&s,g));
 assert(PiPStop(&s)); assert(s.phase==PIPStopping); PiPStopTimeout(&s); assert(s.phase==PIPUnconfirmed);
 assert(!PiPStop(&s)); assert(s.phase==PIPOff); assert(PiPBegin(&s));
 PiPState f={PIPFailed,8}; assert(PiPBegin(&f)&&f.generation==9); return 0;
}
