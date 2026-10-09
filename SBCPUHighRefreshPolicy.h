#ifndef SBCPU_HIGH_REFRESH_POLICY_H
#define SBCPU_HIGH_REFRESH_POLICY_H
#include <stdbool.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

typedef struct { float minimum, maximum, preferred; } SBHRRange;
static inline bool SBHRActive(bool enabled, bool supported) { return enabled && supported; }
static inline int64_t SBHRFPS(int64_t value, bool enabled, bool supported) {
    return SBHRActive(enabled, supported) && value > 59 ? 120 : value;
}
static inline SBHRRange SBHRFrameRange(SBHRRange value, bool enabled, bool supported) {
    // Deliberate safety deviation: non-finite inputs always pass through unchanged.
    if (!SBHRActive(enabled, supported) || !isfinite(value.minimum) ||
        !isfinite(value.maximum) || !isfinite(value.preferred)) return value;
    if ((value.minimum == 0 && value.maximum == 0 && value.preferred == 0) ||
        value.maximum >= 60 || value.preferred >= 60)
        return (SBHRRange){60, 120, 120};
    return value;
}
static inline int64_t SBHRMaximum(int64_t original, bool enabled, bool supported) {
    return SBHRActive(enabled, supported) ? 120 : original;
}
// Fail closed: exact ABI encoding, including implicit self/_cmd and argument count.
// Used by the actual runtime hook installer, not merely a test model.
static inline bool SBHRABI(const char *ret, unsigned count, const char *self,
                           const char *cmd, const char *arg,
                           const char *expectedRet, const char *expectedArg) {
    return ret && self && cmd && expectedRet &&
        count == (expectedArg ? 3u : 2u) &&
        strcmp(ret, expectedRet) == 0 && strcmp(self, "@") == 0 &&
        strcmp(cmd, ":") == 0 &&
        (!expectedArg || (arg && strcmp(arg, expectedArg) == 0));
}
#endif
