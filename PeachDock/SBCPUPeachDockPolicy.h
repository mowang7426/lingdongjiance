#ifndef SBCPU_PEACH_DOCK_POLICY_H
#define SBCPU_PEACH_DOCK_POLICY_H
#include <stdbool.h>
#include <math.h>
// Candidate OS envelope only. Production MUST also pass the complete runtime
// ABI, Dock-only restore, admission and IPC gates before changing any method.
// This is not a claim of on-device verification for every 16.x minor release.
static inline bool SBCPUPeachDockProfileApproved(int major, int minor) {
    return major == 16 && minor >= 0;
}
static inline double SBCPUPeachDockPitch(double width) {
    return isfinite(width) && width > 0 ? width / 4.0 : 0.0;
}
static inline bool SBCPUPeachDockVisualPolicy(bool enabled, bool lowPower,
                                             int thermal, bool reduceMotion,
                                             bool reduceTransparency) {
    return enabled && !lowPower && thermal < 2 &&
           !reduceMotion && !reduceTransparency;
}
#endif
