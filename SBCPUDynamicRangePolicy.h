#ifndef SBCPU_DYNAMIC_RANGE_POLICY_H
#define SBCPU_DYNAMIC_RANGE_POLICY_H
#include <math.h>
/* Keep defaults, malformed requests and >120 ranges untouched. */
static inline int SBCPUDynamicRangeEligible(float min, float max, float preferred) {
    return isfinite(min) && isfinite(max) && isfinite(preferred) &&
        min >= 0 && max > 0 && max <= 120 && min <= max &&
        (preferred == 0 || (preferred >= min && preferred <= max));
}
#endif
