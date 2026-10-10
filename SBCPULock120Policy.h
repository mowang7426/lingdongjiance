#ifndef SBCPU_LOCK120_POLICY_H
#define SBCPU_LOCK120_POLICY_H
#include <stdbool.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

typedef struct { float minimum, maximum, preferred; } SB120Range;
static inline bool SB120Active(bool enabled, int maximum, bool unlocked,
                                bool lowPower, int thermalState) {
    return enabled && maximum >= 120 && unlocked && !lowPower && thermalState < 2;
}
static inline int64_t SB120FPS(int64_t fps, bool active) {
    return active && fps > 60 && fps <= 120 ? 120 : fps;
}
static inline SB120Range SB120SelectRange(SB120Range range, bool active) {
    // Preserve default/low-FPS/invalid ranges. An explicitly high preferred rate
    // (or an unspecified preference with a >60Hz minimum) opts into locking.
    if (active && isfinite(range.minimum) && isfinite(range.maximum) &&
        isfinite(range.preferred) && range.minimum >= 0 &&
        range.maximum >= range.minimum && range.maximum >= 120 &&
        range.maximum <= 120 &&
        ((range.preferred > 60 && range.preferred <= range.maximum &&
          range.preferred >= range.minimum) ||
         (range.preferred == 0 && range.minimum > 60))) {
        SB120Range locked = {120, 120, 120};
        return locked;
    }
    return range;
}
static inline bool SB120ABI(const char *ret, unsigned count, const char *self,
                            const char *cmd, const char *arg,
                            const char *expectedRet, const char *expectedArg) {
    return ret && self && cmd && expectedRet &&
        count == (expectedArg ? 3u : 2u) && !strcmp(ret, expectedRet) &&
        !strcmp(self, "@") && !strcmp(cmd, ":") &&
        (!expectedArg || (arg && !strcmp(arg, expectedArg)));
}
#endif
