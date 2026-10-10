#ifndef UI120_POLICY_H
#define UI120_POLICY_H
#include <stdbool.h>
#include <math.h>
static inline bool U120Eligible(float min, float max, float preferred) {
    if (!isfinite(min) || !isfinite(max) || !isfinite(preferred) ||
        min < 0 || max < min || preferred < 0 || preferred > max) return false;
    return (min == 0 && max == 0 && preferred == 0) || max >= 60 || preferred >= 60;
}
static inline bool U120Safe(bool enabled, int hardware, bool locked,
                            bool lowPower, int thermal, bool mainThread) {
    return enabled && hardware >= 120 && !locked && !lowPower && thermal == 0 && mainThread;
}
#endif
